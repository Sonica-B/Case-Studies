import gradio as gr
import json, os, time, requests, io
import numpy as np
from pathlib import Path
from PIL import Image
from pydub import AudioSegment
from utils_media import video_to_frame_audio, load_audio_16k, log_inference
from fusion import clip_image_probs, wav2vec2_embed_energy, wav2vec2_zero_shot_probs, audio_prior_from_rms, fuse_probs, top1_label_from_probs
from fusion import _ensure_audio_prototypes, _proto_embs

HERE = Path(__file__).parent
lables_PATH = HERE / "labels.json"
CSV_API = HERE / "runs_api.csv"
CSV_LOCAL = HERE / "runs_local.csv"
lables = [x["name"] for x in json.loads(lables_PATH.read_text())["labels"]]
prompts = [x["prompt"] for x in json.loads(lables_PATH.read_text())["labels"]]

# API Models
CLIP_MODEL = "openai/clip-vit-base-patch32"
W2V2_MODEL = "facebook/wav2vec2-base"

# Global HF Token - will be set by user login
USER_HF_TOKEN = None

# ============= API Helper Functions =============
def _img_to_jpeg_bytes(pil: Image.Image) -> bytes:
    buf = io.BytesIO()
    pil.convert("RGB").save(buf, format="JPEG", quality=90)
    return buf.getvalue()

def clip_api_probs(pil: Image.Image, prompts_list=None):
    if prompts_list is None:
        prompts_list = prompts
    if USER_HF_TOKEN is None:
        raise RuntimeError("Please sign in with your HuggingFace token to use API mode.")

    try:
        img_bytes = _img_to_jpeg_bytes(pil)
        url = f"https://api-inference.huggingface.co/models/{CLIP_MODEL}"
        headers = {"Authorization": f"Bearer {USER_HF_TOKEN}"}
        payload = {
            "parameters": {
                "candidate_labels": prompts_list,
                "hypothesis_template": "{}"
            }
        }
        files = {"file": ("image.jpg", img_bytes, "image/jpeg")}
        data = {"inputs": "", "parameters": json.dumps(payload["parameters"])}

        response = requests.post(url, headers=headers, files=files, data=data, timeout=60)
        response.raise_for_status()
        result = response.json()

        if isinstance(result, list) and len(result) > 0:
            scores = {item["label"]: item["score"] for item in result}
        else:
            scores = {p: 1.0/len(prompts_list) for p in prompts_list}

        arr = np.array([scores.get(p, 0.0) for p in prompts_list], dtype=np.float32)
        s = arr.sum()
        arr = arr / s if s > 0 else np.ones_like(arr)/len(arr)
        return arr
    except Exception as e:
        print(f"CLIP API error: {e}")
        return np.ones(len(prompts_list), dtype=np.float32) / len(prompts_list)

def _wave_float32_to_wav_bytes(wave_16k: np.ndarray, sr=16000) -> bytes:
    samples = (np.clip(wave_16k, -1, 1) * 32767.0).astype(np.int16)
    seg = AudioSegment(samples.tobytes(), frame_rate=sr, sample_width=2, channels=1)
    out = io.BytesIO()
    seg.export(out, format="wav")
    return out.getvalue()

def w2v2_api_embed(wave_16k: np.ndarray) -> np.ndarray:
    if USER_HF_TOKEN is None:
        raise RuntimeError("Please sign in with your HuggingFace token to use API mode.")

    wav_bytes = _wave_float32_to_wav_bytes(wave_16k)
    url = f"https://api-inference.huggingface.co/models/{W2V2_MODEL}"
    hdrs = {"Authorization": f"Bearer {USER_HF_TOKEN}"}
    r = requests.post(url, headers=hdrs, data=wav_bytes, timeout=60)
    r.raise_for_status()
    arr = np.asarray(r.json(), dtype=np.float32)
    if arr.ndim == 3:
        arr = arr[0]
    vec = arr.mean(axis=0)
    n = np.linalg.norm(vec) + 1e-8
    return (vec / n).astype(np.float32)

_PROTO_EMBS_API = None

def _synthesize_audio_prototypes_api(sr=16000, dur=2.0):
    def _sine(sr, freq, dur, amp=0.2):
        t = np.linspace(0, dur, int(sr*dur), endpoint=False, dtype=np.float32)
        return (amp * np.sin(2*np.pi*freq*t)).astype(np.float32)

    def _burst_noise(sr, dur, amp=0.2):
        x = np.random.randn(int(sr*dur)).astype(np.float32)
        n = x.size
        env = np.linspace(0, 1, int(0.05*n), dtype=np.float32)
        env = np.pad(env, (0, n-env.size), constant_values=1.0)
        env[-int(0.15*n):] = np.linspace(1, 0, int(0.15*n), dtype=np.float32)
        return (amp * x * env).astype(np.float32)

    def _triad(sr, base, minor=False, dur=2.0, amp=0.18):
        third = 3/2 if minor else 4/3
        w = (_sine(sr, base, dur, amp)
             + _sine(sr, base*third, dur, amp*0.7)
             + _sine(sr, base*2, dur, amp*0.5))
        return (w / (np.max(np.abs(w)) + 1e-6)).astype(np.float32)

    return {
        "calm":      _sine(sr, 220, dur, amp=0.08),
        "energetic": _burst_noise(sr, dur, amp=0.35),
        "suspense":  _sine(sr, 70, dur, amp=0.18) + _sine(sr, 80, dur, amp=0.12),
        "joyful":    _triad(sr, 262, minor=False, dur=dur, amp=0.22),
        "sad":       _triad(sr, 262, minor=True,  dur=dur, amp=0.20),
    }

def _ensure_proto_embs_api():
    global _PROTO_EMBS_API
    if _PROTO_EMBS_API is not None:
        return
    waves = _synthesize_audio_prototypes_api()
    embs = {}
    for lbl, wav in waves.items():
        e = w2v2_api_embed(wav)
        embs[lbl] = e
    _PROTO_EMBS_API = embs

def w2v2_api_zero_shot_probs(wave_16k: np.ndarray, temperature: float = 1.0) -> np.ndarray:
    _ensure_proto_embs_api()
    emb = w2v2_api_embed(wave_16k)
    sims = np.array([float(np.dot(emb, _PROTO_EMBS_API[lbl])) for lbl in lables], dtype=np.float32)
    z = sims / max(1e-6, float(temperature))
    z = z - z.max()
    p = np.exp(z); p /= (p.sum() + 1e-8)
    return p.astype(np.float32)

# ============= Local Prediction Functions =============
def predict_vid(video, alpha=0.7):
    import time, numpy as np
    t0 = time.time()
    frames, wave, meta = video_to_frame_audio(video, target_frames=64, fps_cap=3.0)

    t_img0 = time.time()
    per_frame = []
    for pil in frames:
        per_frame.append(clip_image_probs(pil))  # np[K]
    p_img = np.mean(np.stack(per_frame, axis=0), axis=0)        
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    _, rms = wav2vec2_embed_energy(wave)            # embedding computed; report rms
    p_aud = audio_prior_from_rms(rms)               # np[K]
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label_from_probs(p)
    probs = {k: round(float(v), 4) for k, v in zip(lables, p)}
    lat = {
        "t_image_ms": int(t_img * 1000),
        "t_audio_ms": int(t_aud * 1000),
        "t_fuse_ms":  int(t_fus * 1000),
        "t_total_ms": int((time.time() - t0) * 1000),
        "rms": round(float(rms), 4),
        "n_frames": meta.get("n_frames"),
        "fps_used": round(float(meta.get("fps_used") or 0.0), 3),
        "duration_s": round(float(meta.get("duration_s") or 0.0), 2),
    }
    print("[DEBUG] p_img:", p_img, "p_aud:", p_aud, "fused:", p, "rms:", rms, flush=True)
    log_inference(engine="local", mode="video", alpha=float(alpha), lat=lat, pred=pred, probs=probs, csv_path=CSV_LOCAL)
    return pred, probs, lat

def predict_image_audio_local(image, audio_path, alpha=0.7):
    import time, numpy as np
    t0 = time.time()
    wave = load_audio_16k(audio_path)

    t_img0 = time.time()
    p_img = clip_image_probs(image)
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    p_aud = wav2vec2_zero_shot_probs(wave, temperature=1.0)
    _, rms = wav2vec2_embed_energy(wave)
    p_rms = audio_prior_from_rms(rms)
    p_aud = 0.8 * p_aud + 0.2 * p_rms
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label_from_probs(p)
    probs = {k: float(v) for k, v in zip(lables, p)}
    lat = {
        "t_image_ms": int(t_img*1000),
        "t_audio_ms": int(t_aud*1000),
        "t_fuse_ms":  int(t_fus*1000),
        "t_total_ms": int((time.time()-t0)*1000),
        "rms": round(float(rms), 4),
    }
    print("[DEBUG] p_img:", p_img, "p_aud:", p_aud, "fused:", p, "rms:", rms, flush=True)
    log_inference(engine="local", mode="image_audio", alpha=float(alpha), lat=lat, pred=pred, probs=probs, csv_path=CSV_LOCAL)
    return pred, probs, lat

# ============= API Prediction Functions =============
def predict_vid_api(video, alpha=0.7):
    if USER_HF_TOKEN is None:
        return "Error: Please sign in first", {"error": "HuggingFace token required"}, {"error": "No token"}

    t0 = time.time()
    frames, wave, meta = video_to_frame_audio(video, target_frames=24, fps_cap=2.0)

    t_img0 = time.time()
    per_frame = [clip_api_probs(pil) for pil in frames]
    p_img = np.mean(np.stack(per_frame, axis=0), axis=0)
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    p_aud = w2v2_api_zero_shot_probs(wave, temperature=1.0)
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label_from_probs(p)
    probs = {k: round(float(v), 4) for k, v in zip(lables, p)}
    lat = {
        "t_image_ms": int(t_img*1000),
        "t_audio_ms": int(t_aud*1000),
        "t_fuse_ms":  int(t_fus*1000),
        "t_total_ms": int((time.time()-t0)*1000),
        "n_frames": meta.get("n_frames"),
        "fps_used":  meta.get("fps_used"),
        "duration_s": meta.get("duration_s"),
    }
    log_inference(engine="api", mode="video", alpha=float(alpha), lat=lat, pred=pred, probs=probs, csv_path=CSV_API)
    return pred, probs, lat

def predict_image_audio_api(image, audio_path, alpha=0.7):
    if USER_HF_TOKEN is None:
        return "Error: Please sign in first", {"error": "HuggingFace token required"}, {"error": "No token"}

    t0 = time.time()
    wave = load_audio_16k(audio_path)

    t_img0 = time.time()
    p_img = clip_api_probs(image)
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    p_aud = w2v2_api_zero_shot_probs(wave, temperature=1.0)
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label_from_probs(p)
    probs = {k: round(float(v), 4) for k, v in zip(lables, p)}
    lat = {
        "t_image_ms": int(t_img*1000),
        "t_audio_ms": int(t_aud*1000),
        "t_fuse_ms":  int(t_fus*1000),
        "t_total_ms": int((time.time()-t0)*1000),
    }
    log_inference(engine="api", mode="image_audio", alpha=float(alpha), lat=lat, pred=pred, probs=probs, csv_path=CSV_API)
    return pred, probs, lat

# ============= Wrapper Functions with Mode Selection =============
def predict_video_wrapper(video, alpha, use_api, oauth_token: gr.OAuthToken | None):
    global USER_HF_TOKEN
    if use_api:
        # Get user token from OAuth login
        if oauth_token is not None:
            USER_HF_TOKEN = oauth_token.token
        return predict_vid_api(video, alpha)
    else:
        return predict_vid(video, alpha)

def predict_image_audio_wrapper(image, audio_path, alpha, use_api, oauth_token: gr.OAuthToken | None):
    global USER_HF_TOKEN
    if use_api:
        # Get user token from OAuth login
        if oauth_token is not None:
            USER_HF_TOKEN = oauth_token.token
        return predict_image_audio_api(image, audio_path, alpha)
    else:
        return predict_image_audio_local(image, audio_path, alpha)

# ============= Backward Compatibility Aliases for Tests =============
def predict_image_audio(image, audio_path, alpha=0.7):
    """Backward compatible function for tests - uses local mode"""
    return predict_image_audio_local(image, audio_path, alpha)

def predict_video(video, alpha=0.7):
    """Backward compatible function for tests - uses local mode"""
    return predict_vid(video, alpha)

# ============= Gradio Interface =============
# Only create demo if not being imported for testing
# Check for pytest in sys.modules to detect test environment
import sys
_is_testing = 'pytest' in sys.modules

if not _is_testing:
    with gr.Blocks(title="Scene Mood Detection") as demo:
        with gr.Row():
            gr.Markdown("# 🎬 Scene Mood Classifier\nUpload a short **video** or an **image + audio** pair.")
            gr.LoginButton()

        gr.Markdown("💡 **Tip:** Sign in with HuggingFace to use API mode, or use Local mode without signing in.")
        gr.Markdown("---")

        # Mode Selection
        use_api_mode = gr.Checkbox(
            label="Use API Mode (requires sign-in)",
            value=False,
            info="Unchecked = Local models, Checked = API models"
        )

        with gr.Tab("Video"):
            v = gr.Video(sources=["upload"], height=240)
            alpha_v = gr.Slider(
                minimum=0.0, maximum=1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only."
            )
            btn_v = gr.Button("Analyze")
            out_v1 = gr.Label(label="Prediction")
            out_v2 = gr.JSON(label="Probabilities")
            out_v3 = gr.JSON(label="Latency (ms)")
            btn_v.click(predict_video_wrapper, inputs=[v, alpha_v, use_api_mode], outputs=[out_v1, out_v2, out_v3])

        with gr.Tab("Image + Audio"):
            img = gr.Image(type="pil", height=240)
            aud = gr.Audio(sources=["upload"], type="filepath")
            alpha_ia = gr.Slider(
                minimum=0.0, maximum=1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only."
            )
            btn_ia = gr.Button("Analyze")
            out_i1 = gr.Label(label="Prediction")
            out_i2 = gr.JSON(label="Probabilities")
            out_i3 = gr.JSON(label="Latency (ms)")
            btn_ia.click(predict_image_audio_wrapper, inputs=[img, aud, alpha_ia, use_api_mode], outputs=[out_i1, out_i2, out_i3])

if __name__ == "__main__":
    demo.launch()