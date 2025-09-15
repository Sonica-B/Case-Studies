import gradio as gr
import time
import json
import numpy as np
from pathlib import Path
from utils_media import video_to_frame_audio, load_audio_16k
from fusion import (
    clip_image_probs, wav2vec2_embed_energy,
    audio_prior_from_rms, fuse_probs, top1_label_from_probs
)

HERE = Path(__file__).parent
lables_PATH = HERE / "labels.json"

lables = [x["name"] for x in json.loads(lables_PATH.read_text())["labels"]]

# lables = [x ["name"] for x in json.load(Path("fusion-app/labels.json").read_text())["labels"]]

def predict_vid(video):
    import time, numpy as np
    t0 = time.time()
    frame, wave = video_to_frame_audio(video)

    t_img0 = time.time()
    p_img = clip_image_probs(frame)                 # np[K]
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    _, rms = wav2vec2_embed_energy(wave)            # embedding computed; report rms
    p_aud = audio_prior_from_rms(rms)               # np[K]
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=0.7)
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
    return pred, probs, lat

def predict_image_audio(image, audio_path):
    import time, numpy as np
    t0 = time.time()
    wave = load_audio_16k(audio_path)

    t_img0 = time.time()
    p_img = clip_image_probs(image)
    t_img = time.time() - t_img0

    t_aud0 = time.time()
    _, rms = wav2vec2_embed_energy(wave)
    p_aud = audio_prior_from_rms(rms)
    t_aud = time.time() - t_aud0

    t_fus0 = time.time()
    p = fuse_probs(p_img, p_aud, alpha=0.7)
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
    return pred, probs, lat


with gr.Blocks(title="Scene Mood Detection") as demo:
    gr.Markdown("# Scene Mood Classifier\nUpload a short **video** or an **image + audio** pair.")
    with gr.Tab("Video"):
        v = gr.Video(sources=["upload"], height=240)
        btn_v = gr.Button("Analyze")
        out_v1 = gr.Label(label="Prediction")
        out_v2 = gr.JSON(label="Probabilities")
        out_v3 = gr.JSON(label="Latency (ms)")
        btn_v.click(predict_vid, inputs=[v], outputs=[out_v1,out_v2,out_v3])
    with gr.Tab("Image + Audio"):
        img = gr.Image(type="pil", height=240)
        aud = gr.Audio(sources=["upload"], type="filepath")
        btn_ia = gr.Button("Analyze")
        out_i1 = gr.Label(label="Prediction")
        out_i2 = gr.JSON(label="Probabilities")
        out_i3 = gr.JSON(label="Latency (ms)")
        btn_ia.click(predict_image_audio, inputs=[img, aud], outputs=[out_i1, out_i2, out_i3])

if __name__ == "__main__":
    demo.launch()