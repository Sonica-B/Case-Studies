#!/usr/bin/env python3
"""
Unified Model Gateway - Single endpoint for both API and Local models
Allows toggling between models while keeping both services running
"""

import gradio as gr
import requests
import json
from typing import Any, Dict
import os

# Backend service URLs
API_SERVICE_URL = "http://localhost:5000"
LOCAL_SERVICE_URL = "http://localhost:5003"

# Model selection state
current_model = "api"  # Default to API model

def forward_to_service(fn_name: str, model_type: str, *args, **kwargs):
    """Forward requests to the appropriate backend service"""
    base_url = API_SERVICE_URL if model_type == "api" else LOCAL_SERVICE_URL

    # For Gradio services, we need to handle the prediction endpoint
    # This is a simplified version - in production, you'd handle all endpoints
    try:
        # Gradio uses a specific API structure
        response = requests.post(
            f"{base_url}/run/predict",
            json={"data": args, "fn_index": 0},
            timeout=60
        )
        return response.json()
    except Exception as e:
        return f"Error connecting to {model_type} service: {str(e)}"

def switch_model(choice):
    """Switch between API and Local models"""
    global current_model
    current_model = choice.lower()
    status = f"Switched to {choice} model"

    # Verify the service is running
    try:
        url = API_SERVICE_URL if current_model == "api" else LOCAL_SERVICE_URL
        response = requests.get(f"{url}/health", timeout=5)
        if response.status_code == 200:
            status += " ✅ (Service is healthy)"
        else:
            status += " ⚠️ (Service responded but may have issues)"
    except:
        status += " ❌ (Service not responding - check if it's running)"

    return status

def process_media(image=None, video=None, audio=None):
    """Process media using the currently selected model"""
    global current_model

    # Determine which input was provided
    if image is not None:
        media_type = "image"
        media_data = image
    elif video is not None:
        media_type = "video"
        media_data = video
    elif audio is not None:
        media_type = "audio"
        media_data = audio
    else:
        return "No media provided"

    # Forward to appropriate service
    result = forward_to_service("process", current_model, media_type, media_data)

    return f"[{current_model.upper()} Model] {result}"

# Create Gradio Interface
with gr.Blocks(title="Unified ML Model Gateway") as app:
    gr.Markdown("""
    # 🚀 Unified Model Gateway

    Access both **API** and **Local** models through a single interface!
    Toggle between models without changing URLs or restarting services.
    """)

    with gr.Row():
        with gr.Column(scale=3):
            # Model selector
            model_selector = gr.Radio(
                choices=["API", "Local"],
                value="API",
                label="Select Model",
                info="Choose between API (faster) or Local (private) processing"
            )
            switch_btn = gr.Button("Switch Model", variant="primary")
            status_output = gr.Textbox(label="Status", interactive=False)

        with gr.Column(scale=7):
            # Media inputs
            with gr.Tab("Image"):
                image_input = gr.Image(label="Upload Image", type="pil")
                image_btn = gr.Button("Process Image")

            with gr.Tab("Video"):
                video_input = gr.Video(label="Upload Video")
                video_btn = gr.Button("Process Video")

            with gr.Tab("Audio"):
                audio_input = gr.Audio(label="Upload Audio")
                audio_btn = gr.Button("Process Audio")

            # Output
            output = gr.Textbox(label="Results", lines=10)

    # Event handlers
    switch_btn.click(switch_model, inputs=[model_selector], outputs=[status_output])
    image_btn.click(process_media, inputs=[image_input, None, None], outputs=[output])
    video_btn.click(process_media, inputs=[None, video_input, None], outputs=[output])
    audio_btn.click(process_media, inputs=[None, None, audio_input], outputs=[output])

    # Model indicator
    gr.Markdown("""
    ### How it works:
    - **API Model**: Uses HuggingFace API (requires internet, faster)
    - **Local Model**: Runs on VM (private, no internet needed)
    - Both models stay running - you're just switching which one handles requests

    ### Current Architecture:
    - Gateway (this interface): Port 8000
    - API Model Backend: Port 5000
    - Local Model Backend: Port 5003
    - Only the Gateway needs external exposure via ngrok!
    """)

if __name__ == "__main__":
    app.launch(
        server_name="0.0.0.0",
        server_port=8000,
        share=False
    )