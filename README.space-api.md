---
title: Scene Mood Classifier - API
emoji: 🎬
colorFrom: indigo
colorTo: purple
sdk: gradio
app_file: fusion-app/app_local.py
pinned: false
hf_oauth: true
hf_oauth_scopes:
  - inference-api
---

# 🎬 Scene Mood Classifier - API Mode

Upload a video or image+audio pair to classify the mood/atmosphere of the scene.

## This Space

This space demonstrates the **API-based** version using HuggingFace Inference API.

**Note**: You can also use **Local Mode** without signing in - just uncheck the "Use API Mode" checkbox.

## How to Use

1. **Sign in with Hugging Face** (click the button in the header)
2. The "Use API Mode" checkbox is available - check it to use API mode
3. Upload your video or image+audio pair
4. Click "Analyze"

## About

This app demonstrates multimodal fusion for scene mood classification using CLIP (vision) and Wav2Vec2 (audio) models via the HuggingFace Inference API.
