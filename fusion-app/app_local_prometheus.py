"""
Local Product with Integrated Prometheus Metrics
Following the pattern from rcpaffenroth/DSCS553_example
"""
import time
import torch
from prometheus_client import start_http_server, Counter, Summary, Histogram, Gauge
import gradio as gr

# Import functions from app_local
from app_local import (
    predict_vid as original_predict_vid,
    predict_image_audio_local as original_predict_image_audio_local
)
from fusion import LABELS, PROMPTS

# Initialize Prometheus metrics (same as reference repo)
REQUEST_COUNTER = Counter('ml_requests_total', 'Total number of requests')
SUCCESSFUL_REQUESTS = Counter('ml_successful_requests_total', 'Total successful requests')
FAILED_REQUESTS = Counter('ml_failed_requests_total', 'Total failed requests')
REQUEST_DURATION = Summary('ml_request_duration_seconds', 'Request duration in seconds')

# Additional ML-specific metrics
INFERENCE_COUNTER = Counter('ml_inference_total',
                            'Total number of inferences',
                            ['model_type', 'input_type', 'execution_mode'])
MODEL_LOADED = Gauge('ml_model_loaded',
                    'Model loading status',
                    ['model'])
GPU_AVAILABLE = Gauge('ml_gpu_available', 'GPU availability status')
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
FRAMES_PROCESSED = Counter('ml_frames_processed_total', 'Total frames processed')
AUDIO_SAMPLES = Summary('ml_audio_samples_processed', 'Audio samples processed')

# Set initial GPU status
GPU_AVAILABLE.set(1 if torch.cuda.is_available() else 0)

def predict_vid(video_path, alpha=0.5):
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
        INFERENCE_COUNTER.labels(
            model_type='clip+wav2vec2',
            input_type='video',
            execution_mode='local'
        ).inc()

        # Call original function
        result = original_predict_vid(video_path, alpha)

        # Extract metrics from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result

            # Record prediction confidence
            if probs:
                max_conf = max(probs.values())
                PREDICTION_CONFIDENCE.observe(max_conf)

            # Record frame processing
            if stats and 'frame_count' in stats:
                FRAMES_PROCESSED.inc(stats.get('frame_count', 1))

        # Mark models as loaded (they are lazy-loaded on first use)
        MODEL_LOADED.labels(model='clip').set(1)
        MODEL_LOADED.labels(model='wav2vec2').set(1)

        SUCCESSFUL_REQUESTS.inc()
        return result

    except Exception as e:
        FAILED_REQUESTS.inc()
        ERROR_COUNTER.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        request_timer.observe_duration()
        ACTIVE_USERS.dec()

def predict_image_audio_local(image, audio_path, alpha=0.5):
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
        INFERENCE_COUNTER.labels(
            model_type='clip+wav2vec2',
            input_type='image_audio',
            execution_mode='local'
        ).inc()

        # Call original function
        result = original_predict_image_audio_local(image, audio_path, alpha)

        # Extract metrics from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result

            # Record prediction confidence
            if probs:
                max_conf = max(probs.values())
                PREDICTION_CONFIDENCE.observe(max_conf)

            # Record audio samples
            if stats and 'audio_samples' in stats:
                AUDIO_SAMPLES.observe(stats.get('audio_samples', 16000))

        # Mark models as loaded
        MODEL_LOADED.labels(model='clip').set(1)
        MODEL_LOADED.labels(model='wav2vec2').set(1)

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
with gr.Blocks(title="Scene Mood (Local) - Prometheus") as demo:
    gr.Markdown("# Scene Mood Classifier - Local Version with Prometheus Monitoring")
    gr.Markdown("Upload a short **video** or an **image + audio** pair.")
    gr.Markdown(f"🖥️ Running locally on {'GPU' if torch.cuda.is_available() else 'CPU'}")

    with gr.Tab("Video"):
        v = gr.Video(sources=["upload"], height=240)
        alpha_v = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
            label="Fusion weight α (image ↔ audio)",
            info="α=1 trusts image only; α=0 trusts audio only.")
        btn_v = gr.Button("Analyze")
        out_v1, out_v2, out_v3 = gr.Label(), gr.JSON(), gr.JSON()
        btn_v.click(predict_vid, inputs=[v, alpha_v], outputs=[out_v1, out_v2, out_v3])

    with gr.Tab("Image + Audio"):
        img = gr.Image(type="pil", height=240, label="Image")
        aud = gr.Audio(sources=["upload"], type="filepath", label="Audio")
        alpha_ia = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
            label="Fusion weight α (image ↔ audio)",
            info="α=1 trusts image only; α=0 trusts audio only.")
        btn_ia = gr.Button("Analyze")
        out_i1, out_i2, out_i3 = gr.Label(), gr.JSON(), gr.JSON()
        btn_ia.click(predict_image_audio_local, inputs=[img, aud, alpha_ia], outputs=[out_i1, out_i2, out_i3])

if __name__ == "__main__":
    # Start Prometheus metrics server on port 8000
    start_http_server(8000)
    print("Prometheus metrics server started on port 8000")
    print("Metrics available at http://localhost:8000/metrics")

    # Launch Gradio app on port 5003
    demo.launch(server_name="0.0.0.0", server_port=5003)
    print("Gradio app started on port 5003")