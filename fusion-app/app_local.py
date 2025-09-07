import gradio as gr
import time
import json
import numpy as np
from pathlib import Path
from utils_media import video_to_frame_audio,  load_audio_16k

HERE = Path(__file__).parent
lables_PATH = HERE / "labels.json"

lables = [x["name"] for x in json.loads(lables_PATH.read_text())["labels"]]

# lables = [x ["name"] for x in json.load(Path("fusion-app/labels.json").read_text())["labels"]]

def predict_vid(video):
    t0= time.time()
    frame, audio16k = video_to_frame_audio(video)
    probs = np.ones(len(lables))/len(lables)
    pred = lables[int(np.argmax(probs))]
    lat = {"t_total_ms": int((time.time()-t0)*1000), "note": "decoded media"}
    return pred, {k: float(v) for k,v in zip(lables, probs)}, lat

def predict_aud_img(audio, image):
    t0 = time.time()
    wave = load_audio_16k(audio)
    frame = image
    probs = np.ones(len(lables)) / len(lables)
    pred = lables[int(np.argmax(probs))]
    lat = {"t_total_ms": int((time.time()-t0)*1000), "note": "loaded media"}
    return pred, {k: float(v) for k,v in zip(lables, probs)}, lat


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
        btn_ia.click(predict_aud_img, inputs=[img,aud], outputs=[out_i1,out_i2,out_i3])

if __name__ == "__main__":
    demo.launch()