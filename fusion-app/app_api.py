from __future__ import annotations
import io, os, time, json
from pathlib import Path
from typing import List, Dict
import numpy as np
from PIL import Image
import gradio as gr
import requests
from huggingface_hub import InferenceClient
from pydub import AudioSegment
from utils_media import video_to_frame_audio, load_audio_16k, log_inference

HERE = Path(__file__).parent
LABEL_ITEMS = json.loads((HERE / "labels.json").read_text())["labels"]
LABELS  = [x["name"]   for x in LABEL_ITEMS]
PROMPTS = [x["prompt"] for x in LABEL_ITEMS]   

CLIP_MODEL = "openai/clip-vit-base-patch32"
W2V2_MODEL = "facebook/wav2vec2-base"

HF_TOKEN = os.getenv("HF_Token") 
if not HF_TOKEN:
    raise RuntimeError("Missing HF_Token in environment.")

client = InferenceClient(token=HF_TOKEN)



def _img_to_jpeg_bytes(pil: Image.Image) -> bytes:
    buf = io.BytesIO()
    pil.convert("RGB").save(buf, format="JPEG", quality=90)
    return buf.getvalue()

def clip_api_probs(pil: Image.Image, prompts: List[str] = PROMPTS) -> np.ndarray:

    result = client.zero_shot_image_classification(
        image=pil, candidate_labels=prompts,
        hypothesis_template="{}",               
        model=CLIP_MODEL,
    )
   
    scores = {d["label"]: float(d["score"]) for d in result}
    arr = np.array([scores.get(p, 0.0) for p in prompts], dtype=np.float32)
    
    s = arr.sum();  arr = arr / s if s > 0 else np.ones_like(arr)/len(arr)
    return arr



def _wave_float32_to_wav_bytes(wave_16k: np.ndarray, sr=16000) -> bytes:
    
    samples = (np.clip(wave_16k, -1, 1) * 32767.0).astype(np.int16)
    seg = AudioSegment(
        samples.tobytes(), frame_rate=sr, sample_width=2, channels=1
    )
    out = io.BytesIO()
    seg.export(out, format="wav")
    return out.getvalue()

def w2v2_api_embed(wave_16k: np.ndarray) -> np.ndarray:
    wav_bytes = _wave_float32_to_wav_bytes(wave_16k)

    url = f"https://api-inference.huggingface.co/models/{W2V2_MODEL}"
    hdrs = {"Authorization": f"Bearer {HF_TOKEN}"}
    r = requests.post(url, headers=hdrs, data=wav_bytes, timeout=60)
    r.raise_for_status()
    arr = np.asarray(r.json(), dtype=np.float32)  # shape [T, 768]
    if arr.ndim == 3:      # [batch, T, D]
        arr = arr[0]
    vec = arr.mean(axis=0)  # [768]
    # L2 normalize
    n = np.linalg.norm(vec) + 1e-8
    return (vec / n).astype(np.float32)



_PROTO_EMBS: Dict[str, np.ndarray] | None = None

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

def _synthesize_audio_prototypes(sr=16000, dur=2.0):
    return {
        "calm":      _sine(sr, 220, dur, amp=0.08),
        "energetic": _burst_noise(sr, dur, amp=0.35),
        "suspense":  _sine(sr, 70, dur, amp=0.18) + _sine(sr, 80, dur, amp=0.12),
        "joyful":    _triad(sr, 262, minor=False, dur=dur, amp=0.22),
        "sad":       _triad(sr, 262, minor=True,  dur=dur, amp=0.20),
    }

def _ensure_proto_embs():
    global _PROTO_EMBS
    if _PROTO_EMBS is not None:
        return
    waves = _synthesize_audio_prototypes()
    embs = {}
    for lbl, wav in waves.items():
        e = w2v2_api_embed(wav)  # API embed L2-normalized
        embs[lbl] = e
    _PROTO_EMBS = embs

def w2v2_api_zero_shot_probs(wave_16k: np.ndarray, temperature: float = 1.0) -> np.ndarray:
    _ensure_proto_embs()
    emb = w2v2_api_embed(wave_16k)  # [768], normalized
    sims = np.array([float(np.dot(emb, _PROTO_EMBS[lbl])) for lbl in LABELS], dtype=np.float32)
    z = sims / max(1e-6, float(temperature))
    z = z - z.max()
    p = np.exp(z);  p /= (p.sum() + 1e-8)
    return p.astype(np.float32)


def fuse_probs(p_img: np.ndarray, p_aud: np.ndarray, alpha: float) -> np.ndarray:
    p_img = p_img / (p_img.sum() + 1e-8)
    p_aud = p_aud / (p_aud.sum() + 1e-8)
    p = alpha * p_img + (1 - alpha) * p_aud
    return p / (p.sum() + 1e-8)

def top1_label(p: np.ndarray) -> str:
    return LABELS[int(np.argmax(p))]

def predict_video(video, alpha=0.7):
    t0 = time.time()

    # FULL video analysis
    frames, wave, meta = video_to_frame_audio(video, target_frames=24, fps_cap=2.0)

    # IMAGE
    t_img0 = time.time()
    per_frame = [clip_api_probs(pil) for pil in frames]
    p_img = np.mean(np.stack(per_frame, axis=0), axis=0)
    t_img = time.time() - t_img0

    # AUDIO
    t_aud0 = time.time()
    p_aud = w2v2_api_zero_shot_probs(wave, temperature=1.0)
    t_aud = time.time() - t_aud0

    # FUSION
    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label(p)
    probs = {k: round(float(v), 4) for k, v in zip(LABELS, p)}
    lat = {
        "t_image_ms": int(t_img*1000),
        "t_audio_ms": int(t_aud*1000),
        "t_fuse_ms":  int(t_fus*1000),
        "t_total_ms": int((time.time()-t0)*1000),
        "n_frames": meta.get("n_frames"),
        "fps_used":  meta.get("fps_used"),
        "duration_s": meta.get("duration_s"),
    }
    log_inference(engine="api", mode="video", alpha=float(alpha), lat=lat, pred=pred, probs=probs)
    return pred, probs, lat

def predict_image_audio(image: Image.Image, audio_path: str, alpha=0.7):
    t0 = time.time()
    wave = load_audio_16k(audio_path)

    # IMAGE
    t_img0 = time.time()
    p_img = clip_api_probs(image)
    t_img = time.time() - t_img0

    # AUDIO
    t_aud0 = time.time()
    p_aud = w2v2_api_zero_shot_probs(wave, temperature=1.0)
    t_aud = time.time() - t_aud0

    # FUSION
    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=float(alpha))
    t_fus = time.time() - t_fus0

    pred = top1_label(p)
    probs = {k: round(float(v), 4) for k, v in zip(LABELS, p)}
    lat = {
        "t_image_ms": int(t_img*1000),
        "t_audio_ms": int(t_aud*1000),
        "t_fuse_ms":  int(t_fus*1000),
        "t_total_ms": int((time.time()-t0)*1000),
    }
    log_inference(engine="api", mode="image_audio", alpha=float(alpha), lat=lat, pred=pred, probs=probs)
    return pred, probs, lat

'''
Chat GPT : Create Gradio interface for the above API functions same as local app.
'''
with gr.Blocks(title="Scene Mood (API)") as demo:
    gr.Markdown("# Scene Mood Classifier - API Version. Upload a short **video** or an **image + audio** pair.")
    with gr.Tab("Video"):
        v = gr.Video(sources=["upload"], height=240)
        alpha_v = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
            label="Fusion weight α (image ↔ audio)",
            info="α=1 trusts image only; α=0 trusts audio only.")
        btn_v = gr.Button("Analyze")
        out_v1, out_v2, out_v3 = gr.Label(), gr.JSON(), gr.JSON()
        btn_v.click(predict_video, inputs=[v, alpha_v], outputs=[out_v1, out_v2, out_v3])

    with gr.Tab("Image + Audio"):
        img = gr.Image(type="pil", height=240, label="Image")
        aud = gr.Audio(sources=["upload"], type="filepath", label="Audio")
        alpha_ia = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
            label="Fusion weight α (image ↔ audio)",
            info="α=1 trusts image only; α=0 trusts audio only.")
        btn_ia = gr.Button("Analyze")
        out_i1, out_i2, out_i3 = gr.Label(), gr.JSON(), gr.JSON()
        btn_ia.click(predict_image_audio, inputs=[img, aud, alpha_ia], outputs=[out_i1, out_i2, out_i3])

if __name__ == "__main__":
    demo.launch()
