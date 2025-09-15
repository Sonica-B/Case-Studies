import gradio as gr
import json
from pathlib import Path
from utils_media import video_to_frame_audio, load_audio_16k, log_inference
from fusion import clip_image_probs, wav2vec2_embed_energy, wav2vec2_zero_shot_probs, audio_prior_from_rms, fuse_probs, top1_label_from_probs

HERE = Path(__file__).parent
lables_PATH = HERE / "labels.json"

lables = [x["name"] for x in json.loads(lables_PATH.read_text())["labels"]]

# lables = [x ["name"] for x in json.load(Path("fusion-app/labels.json").read_text())["labels"]]

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
    log_inference(engine="local", mode="video", alpha=float(alpha), lat=lat, pred=pred, probs=probs)
    return pred, probs, lat

def predict_image_audio(image, audio_path, alpha=0.7):
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
    log_inference(engine="local", mode="image_audio", alpha=float(alpha), lat=lat, pred=pred, probs=probs)
    return pred, probs, lat


with gr.Blocks(title="Scene Mood Detection") as demo:
    gr.Markdown("# Scene Mood Classifier - Local \nUpload a short **video** or an **image + audio** pair.")
    with gr.Tab("Video"):
        v = gr.Video(sources=["upload"], height=240)


# Chat GPT : Create Gradio slider for alpha value with label "Fusion weight α (image ↔ audio)" and info "α=1 trusts image only; α=0 trusts audio only."
        alpha_v = gr.Slider(
        minimum=0.0, maximum=1.0, value=0.7, step=0.05,
        label="Fusion weight α (image ↔ audio)",
        info="α=1 trusts image only; α=0 trusts audio only."
       )
        

        btn_v = gr.Button("Analyze")
        out_v1 = gr.Label(label="Prediction")
        out_v2 = gr.JSON(label="Probabilities")
        out_v3 = gr.JSON(label="Latency (ms)")
        btn_v.click(predict_vid, inputs=[v, alpha_v], outputs=[out_v1, out_v2, out_v3])

    with gr.Tab("Image + Audio"):
        img = gr.Image(type="pil", height=240)
        aud = gr.Audio(sources=["upload"], type="filepath")

# Chat GPT : Create Gradio slider for alpha value with label "Fusion weight α (image ↔ audio)" and info "α=1 trusts image only; α=0 trusts audio only."
        alpha_ia = gr.Slider(
        minimum=0.0, maximum=1.0, value=0.7, step=0.05,
        label="Fusion weight α (image ↔ audio)",
        info="α=1 trusts image only; α=0 trusts audio only."
        )

        btn_ia = gr.Button("Analyze")
        out_i1 = gr.Label(label="Prediction")
        out_i2 = gr.JSON(label="Probabilities")
        out_i3 = gr.JSON(label="Latency (ms)")
        btn_ia.click(predict_image_audio, inputs=[img, aud, alpha_ia], outputs=[out_i1, out_i2, out_i3])

if __name__ == "__main__":
    demo.launch()