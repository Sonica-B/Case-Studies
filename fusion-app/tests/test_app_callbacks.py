import types
import numpy as np
from PIL import Image
import importlib
import builtins
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).parent.parent))

app = importlib.import_module("app_local")

# Utility to get function by trying multiple possible names
def get_fn(mod, *names):
    for n in names:
        if hasattr(mod, n):
            return getattr(mod, n)
    raise AttributeError(f"None of {names} found in {mod.__name__}")

predict_video = get_fn(app, "predict_video", "predict_vid")
predict_image_audio = get_fn(app, "predict_image_audio")

def test_predict_image_audio_fuses_correctly(monkeypatch):
    K = len(app.lables)
    # deterministic distributions
    p_img = np.zeros(K); p_img[0] = 1.0     # image votes class 0
    p_aud = np.zeros(K); p_aud[1] = 1.0     # audio votes class 1

    # Monkeypatch heavy parts to lightweight stubs
    monkeypatch.setattr(app, "clip_image_probs", lambda img, **kw: p_img, raising=True)
   
    if hasattr(app, "wav2vec2_zero_shot_probs"):
        monkeypatch.setattr(app, "wav2vec2_zero_shot_probs", lambda wave, **kw: p_aud, raising=True)
    if hasattr(app, "audio_prior_from_rms"):
        monkeypatch.setattr(app, "audio_prior_from_rms", lambda rms: p_aud, raising=False)
    if hasattr(app, "wav2vec2_embed_energy"):
        monkeypatch.setattr(app, "wav2vec2_embed_energy", lambda wave: (np.zeros(768, dtype=np.float32), 0.5), raising=True)
    monkeypatch.setattr(app, "load_audio_16k", lambda path: np.zeros(16000, dtype=np.float32), raising=True)
    monkeypatch.setattr(app, "log_inference", lambda **kw: None, raising=False)  # no file writes

    # dummy inputs
    dummy_img = Image.new("RGB", (64, 64), color=128)
    dummy_audio_path = "dummy.wav"

   
    pred_hi, probs_hi, _ = predict_image_audio(dummy_img, dummy_audio_path, 0.9)
   
    pred_lo, probs_lo, _ = predict_image_audio(dummy_img, dummy_audio_path, 0.1)

    # Indexes for label 0/1
    idx0 = 0
    idx1 = 1

    assert probs_hi[app.lables[idx0]] > probs_hi[app.lables[idx1]]
    assert probs_lo[app.lables[idx1]] > probs_lo[app.lables[idx0]]
    assert 0.99 <= sum(probs_hi.values()) <= 1.01
    assert 0.99 <= sum(probs_lo.values()) <= 1.01
    assert isinstance(pred_hi, str) and isinstance(pred_lo, str)

def test_predict_video_path_runs_with_stubs(monkeypatch):
    K = len(app.lables)
    p_img = np.zeros(K); p_img[-1] = 1.0   # image favors last class
    p_aud = np.zeros(K); p_aud[0]  = 1.0   # audio favors first class

    # Stub frame extractor to avoid ffmpeg
    frames = [Image.new("RGB", (32, 32), c) for c in [(255,0,0)]*5]
    wave = np.zeros(16000, dtype=np.float32)
    meta = {"n_frames":5, "fps_used":1.0, "duration_s":5.0}
    # Mock the video_to_frame_audio function that's imported from utils_media
    monkeypatch.setattr(app, "video_to_frame_audio", lambda v, **kw: (frames, wave, meta), raising=True)

    # Stub models
    monkeypatch.setattr(app, "clip_image_probs", lambda pil, **kw: p_img, raising=True)
    if hasattr(app, "wav2vec2_zero_shot_probs"):
        monkeypatch.setattr(app, "wav2vec2_zero_shot_probs", lambda w, **kw: p_aud, raising=True)
    if hasattr(app, "wav2vec2_embed_energy"):
        monkeypatch.setattr(app, "wav2vec2_embed_energy", lambda w: (np.zeros(768, dtype=np.float32), 0.3), raising=True)
    monkeypatch.setattr(app, "log_inference", lambda **kw: None, raising=False)

    # Call
    pred, probs, lat = predict_video("dummy.mp4", 0.5)

    # Checks
    assert isinstance(pred, str)
    assert set(probs.keys()) == set(app.lables)
    assert "t_total_ms" in lat and "n_frames" in lat or "t_total_ms" in lat
