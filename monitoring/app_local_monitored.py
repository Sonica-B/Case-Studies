"""
Local Product with Prometheus Monitoring
This wraps the local application with Prometheus metrics
"""
import time
import os
import sys
sys.path.append('/app')

from prometheus_client import Counter, Histogram, Gauge, Summary
import threading
import torch

# Prometheus metrics
inference_counter = Counter('ml_inference_total',
                           'Total number of inferences',
                           ['model', 'mode', 'execution_type'])
inference_duration = Histogram('ml_inference_duration_seconds',
                               'Inference duration in seconds',
                               ['model', 'mode'],
                               buckets=(0.1, 0.5, 1.0, 2.5, 5.0, 10.0))
error_counter = Counter('ml_errors_total',
                       'Total number of errors',
                       ['error_type'])
active_users = Gauge('ml_active_users', 'Number of active users')
model_loaded = Gauge('ml_model_loaded', 'Model loaded status', ['model'])
model_memory_usage = Gauge('ml_model_memory_bytes',
                          'Model memory usage in bytes',
                          ['model'])
gpu_available = Gauge('ml_gpu_available', 'GPU availability')
fusion_alpha_histogram = Histogram('ml_fusion_alpha',
                                  'Distribution of fusion alpha values',
                                  buckets=(0, 0.2, 0.4, 0.6, 0.8, 1.0))
prediction_confidence = Histogram('ml_prediction_confidence',
                                 'Confidence scores of predictions',
                                 ['mood'])
frames_processed = Counter('ml_frames_processed_total',
                           'Total frames processed in video analysis')
audio_samples_processed = Summary('ml_audio_samples_processed',
                                 'Audio samples processed')

# Import necessary modules
import gradio as gr
from fusion_app import fusion
from fusion_app import app_local
from fusion_app.utils_media import video_to_frame_audio, load_audio_16k

# Monkey-patch the local prediction functions to add metrics
original_predict_vid = app_local.predict_vid
original_predict_image_audio_local = app_local.predict_image_audio_local

def monitored_predict_vid(video_path, alpha=0.5):
    """Wrapped video prediction with metrics"""
    start_time = time.time()
    active_users.inc()

    try:
        # Call original function
        result = original_predict_vid(video_path, alpha)

        # Record metrics
        inference_counter.labels(
            model='clip+wav2vec2',
            mode='video',
            execution_type='local'
        ).inc()
        fusion_alpha_histogram.observe(alpha)

        # Extract confidence and frame count from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                max_mood = max(probs, key=probs.get)
                prediction_confidence.labels(mood=max_mood).observe(max_conf)
            # Count frames from stats
            if stats and 'image_ms' in stats:
                frames_processed.inc(stats.get('frame_count', 1))

        duration = time.time() - start_time
        inference_duration.labels(
            model='clip+wav2vec2',
            mode='video'
        ).observe(duration)

        return result

    except Exception as e:
        error_counter.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        active_users.dec()

def monitored_predict_image_audio_local(image, audio_path, alpha=0.5):
    """Wrapped image+audio prediction with metrics"""
    start_time = time.time()
    active_users.inc()

    try:
        # Call original function
        result = original_predict_image_audio_local(image, audio_path, alpha)

        # Record metrics
        inference_counter.labels(
            model='clip+wav2vec2',
            mode='image_audio',
            execution_type='local'
        ).inc()
        fusion_alpha_histogram.observe(alpha)

        # Extract confidence from result
        if isinstance(result, tuple) and len(result) > 1:
            pred, probs, stats = result
            if probs:
                max_conf = max(probs.values())
                max_mood = max(probs, key=probs.get)
                prediction_confidence.labels(mood=max_mood).observe(max_conf)
            # Track audio samples
            if stats and 'audio_ms' in stats:
                audio_samples_processed.observe(stats.get('audio_samples', 16000))

        duration = time.time() - start_time
        inference_duration.labels(
            model='clip+wav2vec2',
            mode='image_audio'
        ).observe(duration)

        return result

    except Exception as e:
        error_counter.labels(error_type=type(e).__name__).inc()
        raise
    finally:
        active_users.dec()

# Replace functions with monitored versions
app_local.predict_vid = monitored_predict_vid
app_local.predict_image_audio_local = monitored_predict_image_audio_local

# Set initial metrics
gpu_available.set(1 if torch.cuda.is_available() else 0)
model_loaded.labels(model='clip').set(0)  # Will be set to 1 when loaded
model_loaded.labels(model='wav2vec2').set(0)  # Will be set to 1 when loaded

# Monitor model loading
original_lazy_load = fusion._lazy_load_models

def monitored_lazy_load():
    """Monitor model loading"""
    result = original_lazy_load()
    model_loaded.labels(model='clip').set(1)
    model_loaded.labels(model='wav2vec2').set(1)

    # Estimate memory usage (rough estimates)
    if torch.cuda.is_available():
        # GPU memory
        model_memory_usage.labels(model='clip').set(500 * 1024 * 1024)  # ~500MB
        model_memory_usage.labels(model='wav2vec2').set(400 * 1024 * 1024)  # ~400MB
    else:
        # CPU memory
        model_memory_usage.labels(model='clip').set(600 * 1024 * 1024)  # ~600MB
        model_memory_usage.labels(model='wav2vec2').set(450 * 1024 * 1024)  # ~450MB

    return result

fusion._lazy_load_models = monitored_lazy_load

if __name__ == "__main__":
    # Launch the local app with monitoring
    print("Starting locally executed product with Prometheus monitoring...")
    print("Metrics available at http://localhost:8001/metrics")
    print("Gradio UI available at http://localhost:7861")
    print(f"GPU Available: {torch.cuda.is_available()}")

    # Create Gradio interface with monitored functions
    with gr.Blocks(title="Scene Mood (Local) - Monitored") as demo:
        gr.Markdown("# Scene Mood Classifier - Local Version with Monitoring")
        gr.Markdown("Upload a short **video** or an **image + audio** pair.")
        gr.Markdown(f"🖥️ Running locally on {'GPU' if torch.cuda.is_available() else 'CPU'}")

        with gr.Tab("Video"):
            v = gr.Video(sources=["upload"], height=240)
            alpha_v = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only.")
            btn_v = gr.Button("Analyze")
            out_v1, out_v2, out_v3 = gr.Label(), gr.JSON(), gr.JSON()
            btn_v.click(monitored_predict_vid, inputs=[v, alpha_v], outputs=[out_v1, out_v2, out_v3])

        with gr.Tab("Image + Audio"):
            img = gr.Image(type="pil", height=240, label="Image")
            aud = gr.Audio(sources=["upload"], type="filepath", label="Audio")
            alpha_ia = gr.Slider(0.0, 1.0, value=0.7, step=0.05,
                label="Fusion weight α (image ↔ audio)",
                info="α=1 trusts image only; α=0 trusts audio only.")
            btn_ia = gr.Button("Analyze")
            out_i1, out_i2, out_i3 = gr.Label(), gr.JSON(), gr.JSON()
            btn_ia.click(monitored_predict_image_audio_local, inputs=[img, aud, alpha_ia], outputs=[out_i1, out_i2, out_i3])

    demo.launch(server_name="0.0.0.0", server_port=7861)