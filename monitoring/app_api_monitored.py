"""
API-based Product with Prometheus Monitoring
This wraps the API-based application with Prometheus metrics
"""
import time
import os
import sys
sys.path.append('/app')

from prometheus_client import Counter, Histogram, Gauge, generate_latest
import threading

# Prometheus metrics
inference_counter = Counter('ml_inference_total',
                           'Total number of inferences',
                           ['model', 'mode'])
inference_duration = Histogram('ml_inference_duration_seconds',
                               'Inference duration in seconds',
                               ['model', 'mode'])
error_counter = Counter('ml_errors_total',
                       'Total number of errors',
                       ['error_type'])
active_users = Gauge('ml_active_users', 'Number of active users')
model_loaded = Gauge('ml_model_loaded', 'Model loaded status', ['model'])
api_calls_counter = Counter('ml_api_calls_total',
                           'Total API calls to HuggingFace',
                           ['model'])
fusion_alpha_histogram = Histogram('ml_fusion_alpha',
                                  'Distribution of fusion alpha values')
prediction_confidence = Histogram('ml_prediction_confidence',
                                 'Confidence scores of predictions',
                                 ['mood'])

# Import necessary modules
import gradio as gr
# Import original functions from app_api
from fusion_app.app_api import (
    predict_video as original_predict_video,
    predict_image_audio as original_predict_image_audio,
    LABELS, PROMPTS
)

def monitored_predict_video(video_path, alpha=0.5):
    """Wrapped video prediction with metrics"""
    start_time = time.time()
    active_users.inc()

    try:
        # Call original function
        result = original_predict_video(video_path, alpha)

        # Record metrics
        inference_counter.labels(model='clip+wav2vec2', mode='video').inc()
        api_calls_counter.labels(model='clip').inc()
        api_calls_counter.labels(model='wav2vec2').inc()
        fusion_alpha_histogram.observe(alpha)

        # Extract confidence from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                max_mood = max(probs, key=probs.get)
                prediction_confidence.labels(mood=max_mood).observe(max_conf)

        duration = time.time() - start_time
        inference_duration.labels(model='clip+wav2vec2', mode='video').observe(duration)

        return result

    except Exception as e:
        error_counter.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        active_users.dec()

def monitored_predict_image_audio(image_path, audio_path, alpha=0.5):
    """Wrapped image+audio prediction with metrics"""
    start_time = time.time()
    active_users.inc()

    try:
        # Call original function
        result = original_predict_image_audio(image_path, audio_path, alpha)

        # Record metrics
        inference_counter.labels(model='clip+wav2vec2', mode='image_audio').inc()
        api_calls_counter.labels(model='clip').inc()
        api_calls_counter.labels(model='wav2vec2').inc()
        fusion_alpha_histogram.observe(alpha)

        # Extract confidence from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                max_mood = max(probs, key=probs.get)
                prediction_confidence.labels(mood=max_mood).observe(max_conf)

        duration = time.time() - start_time
        inference_duration.labels(model='clip+wav2vec2', mode='image_audio').observe(duration)

        return result

    except Exception as e:
        error_counter.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        active_users.dec()

# Set model loaded status
model_loaded.labels(model='clip').set(1)  # API models are always "loaded"
model_loaded.labels(model='wav2vec2').set(1)

if __name__ == "__main__":
    # Launch the original Gradio app with monitoring
    print("Starting API-based product with Prometheus monitoring...")
    print("Metrics available at http://localhost:8000/metrics")
    print("Gradio UI available at http://localhost:7860")

    # Get HF token from environment
    hf_token = os.environ.get("HF_TOKEN")
    if not hf_token:
        print("Warning: HF_TOKEN not set. API calls may fail.")

    # Create Gradio interface with monitored functions
    with gr.Blocks(title="Scene Mood (API) - Monitored") as demo:
        gr.Markdown("# Scene Mood Classifier - API Version with Monitoring")
        gr.Markdown("Upload a short **video** or an **image + audio** pair.")

        with gr.Tab("Video"):
            v = gr.Video(sources=["upload"], height=240)
            alpha_v = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only.")
            btn_v = gr.Button("Analyze")
            out_v1, out_v2, out_v3 = gr.Label(), gr.JSON(), gr.JSON()
            btn_v.click(monitored_predict_video, inputs=[v, alpha_v], outputs=[out_v1, out_v2, out_v3])

        with gr.Tab("Image + Audio"):
            img = gr.Image(type="pil", height=240, label="Image")
            aud = gr.Audio(sources=["upload"], type="filepath", label="Audio")
            alpha_ia = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only.")
            btn_ia = gr.Button("Analyze")
            out_i1, out_i2, out_i3 = gr.Label(), gr.JSON(), gr.JSON()
            btn_ia.click(monitored_predict_image_audio, inputs=[img, aud, alpha_ia], outputs=[out_i1, out_i2, out_i3])

    demo.launch(server_name="0.0.0.0", server_port=7860)