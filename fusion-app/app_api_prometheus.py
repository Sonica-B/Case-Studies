"""
API-based Product with Integrated Prometheus Metrics
Following the pattern from rcpaffenroth/DSCS553_example
"""
import os
import time
from prometheus_client import start_http_server, Counter, Summary, Histogram, Gauge
import gradio as gr
from huggingface_hub import InferenceClient
import numpy as np
from PIL import Image

# Import functions from app_api
from app_api import (
    LABELS, PROMPTS, temperature,
    clip_api_probs, w2v2_api_embed, w2v2_api_zero_shot_probs,
    fuse_probs, predict_video as original_predict_video,
    predict_image_audio as original_predict_image_audio
)

# Initialize Prometheus metrics
REQUEST_COUNTER = Counter('ml_requests_total', 'Total number of requests')
SUCCESSFUL_REQUESTS = Counter('ml_successful_requests_total', 'Total successful requests')
FAILED_REQUESTS = Counter('ml_failed_requests_total', 'Total failed requests')
REQUEST_DURATION = Summary('ml_request_duration_seconds', 'Request duration in seconds')

# Additional metrics specific to ML
INFERENCE_COUNTER = Counter('ml_inference_total',
                            'Total number of inferences',
                            ['model_type', 'input_type'])
API_CALLS = Counter('ml_api_calls_total',
                   'Total API calls to HuggingFace',
                   ['model'])
FUSION_ALPHA = Histogram('ml_fusion_alpha',
                         'Distribution of fusion alpha values',
                         buckets=(0, 0.2, 0.4, 0.6, 0.8, 1.0))
PREDICTION_CONFIDENCE = Histogram('ml_prediction_confidence',
                                 'Confidence scores of predictions',
                                 buckets=(0.1, 0.3, 0.5, 0.7, 0.9, 1.0))
ERROR_COUNTER = Counter('ml_errors_by_type',
                       'Errors by type',
                       ['error_type'])
ACTIVE_USERS = Gauge('ml_active_users', 'Number of active users')

def predict_video(video_path, alpha=0.5):
    """
    Predict mood from video with Prometheus monitoring
    """
    REQUEST_COUNTER.inc()
    ACTIVE_USERS.inc()
    request_timer = REQUEST_DURATION.time()

    try:
        # Record fusion alpha
        FUSION_ALPHA.observe(alpha)

        # Perform inference
        INFERENCE_COUNTER.labels(model_type='clip+wav2vec2', input_type='video').inc()
        API_CALLS.labels(model='clip').inc()
        API_CALLS.labels(model='wav2vec2').inc()

        # Call original function
        result = original_predict_video(video_path, alpha)

        # Extract confidence if available
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                PREDICTION_CONFIDENCE.observe(max_conf)

        SUCCESSFUL_REQUESTS.inc()
        return result

    except Exception as e:
        FAILED_REQUESTS.inc()
        ERROR_COUNTER.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        request_timer.observe_duration()
        ACTIVE_USERS.dec()

def predict_image_audio(image, audio_path, alpha=0.5):
    """
    Predict mood from image and audio with Prometheus monitoring
    """
    REQUEST_COUNTER.inc()
    ACTIVE_USERS.inc()
    request_timer = REQUEST_DURATION.time()

    try:
        # Record fusion alpha
        FUSION_ALPHA.observe(alpha)

        # Perform inference
        INFERENCE_COUNTER.labels(model_type='clip+wav2vec2', input_type='image_audio').inc()
        API_CALLS.labels(model='clip').inc()
        API_CALLS.labels(model='wav2vec2').inc()

        # Call original function
        result = original_predict_image_audio(image, audio_path, alpha)

        # Extract confidence if available
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                PREDICTION_CONFIDENCE.observe(max_conf)

        SUCCESSFUL_REQUESTS.inc()
        return result

    except Exception as e:
        FAILED_REQUESTS.inc()
        ERROR_COUNTER.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        request_timer.observe_duration()
        ACTIVE_USERS.dec()

# Create Gradio interface
with gr.Blocks(title="Scene Mood (API) - Prometheus") as demo:
    gr.Markdown("# Scene Mood Classifier - API Version with Prometheus Monitoring")
    gr.Markdown("Upload a short **video** or an **image + audio** pair.")

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
    # Start Prometheus metrics server on port 8000
    start_http_server(8000)
    print("Prometheus metrics server started on port 8000")
    print("Metrics available at http://localhost:8000/metrics")

    # Launch Gradio app on port 5000
    demo.launch(server_name="0.0.0.0", server_port=5000)
    print("Gradio app started on port 5000")