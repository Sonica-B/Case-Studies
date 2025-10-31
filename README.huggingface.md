---
title: Scene Mood Classifier
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

# 🎬 Scene Mood Classifier

Upload a video or image+audio pair to classify the mood/atmosphere of the scene.

## Features

- **Local Mode** (default): Uses locally downloaded models - works without login
- **API Mode**: Uses HuggingFace Inference API - requires sign-in with HuggingFace account

## How to Use

1. **For Local Mode**: Just upload your media and analyze (no login needed)
2. **For API Mode**:
   - Click the "Sign in with Hugging Face" button
   - Check "Use API Mode" checkbox
   - Upload and analyze

## About

This app demonstrates multimodal fusion for scene mood classification using CLIP (vision) and Wav2Vec2 (audio) models.
