from pathlib import Path
import json
import numpy as np
import torch
from transformers import CLIPProcessor, CLIPModel, Wav2Vec2Processor, Wav2Vec2Model

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

_here = Path(__file__).parent
_labels = json.loads((_here / "labels.json").read_text())["labels"]
LABELS = [x["name"] for x in _labels]
PROMPTS = [x["prompt"] for x in _labels]

_clip_model = None
_clip_proc = None
_wav_model = None
_wav_proc = None

def _lazy_load_models():
    global _clip_model, _clip_proc, _wav_model, _wav_proc
    if _clip_model is None:
        _clip_model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32").to(DEVICE)
        _clip_model.eval()
        _clip_proc = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
    if _wav_model is None:
        _wav_model = Wav2Vec2Model.from_pretrained("facebook/wav2vec2-base").to(DEVICE)
        _wav_model.eval()
        _wav_proc = Wav2Vec2Processor.from_pretrained("facebook/wav2vec2-base")

# image branch (CLIP) 
@torch.no_grad()
def clip_image_probs(pil_image, prompts=PROMPTS):

    _lazy_load_models()
    # text features
    text_inputs = _clip_proc(text=prompts, return_tensors="pt", padding=True).to(DEVICE)
    text_feats = _clip_model.get_text_features(**text_inputs)  # [K, d]
    text_feats = torch.nn.functional.normalize(text_feats, dim=-1)

    # image features
    img_inputs = _clip_proc(images=pil_image, return_tensors="pt").to(DEVICE)
    img_feats = _clip_model.get_image_features(**img_inputs)   # [1, d]
    img_feats = torch.nn.functional.normalize(img_feats, dim=-1)

    # similarity to softmax
    sims = (img_feats @ text_feats.T).squeeze(0)               # [K]
    probs = torch.softmax(sims, dim=-1)                        # [K]
    return probs.detach().cpu().numpy()                        # np.float32[K]

# audio branch (Wav2Vec2 + energy prior)
@torch.no_grad()
def wav2vec2_embed_energy(wave_16k: np.ndarray):
    _lazy_load_models()
    # wave_16k must be float32 mono in [-1, 1]
    inp = _wav_proc(wave_16k, sampling_rate=16000, return_tensors="pt").to(DEVICE)
    out = _wav_model(**inp).last_hidden_state    # [1, T, 768]
    emb = out.mean(dim=1).squeeze(0)            # [768]
    emb = torch.nn.functional.normalize(emb, dim=-1)
    emb_np = emb.detach().cpu().numpy()

    # simple loudness proxy (RMS)
    rms = float(np.sqrt(np.mean(np.square(wave_16k))))  # 0..~1
    return emb_np, rms

def audio_prior_from_rms(rms: float) -> np.ndarray:
    # clamp
    r = max(0.0, min(1.0, rms))
    # weights via curves
    calm = max(0.0, 1.0 - 2.0*r)          # high when quiet
    sad  = max(0.0, 1.2 - 2.2*r)
    energetic = r**0.8                     # grows with loudness
    joyful = (r**0.9) * 0.9 + 0.1*(1-r)   # energetic but with a small bias
    suspense = 0.6*(1.0 - abs(r - 0.5)*2) # middle loudness means suspense

    vec = np.array([calm, energetic, suspense, joyful, sad], dtype=np.float32)
    vec = np.clip(vec, 1e-4, None)
    vec = vec / vec.sum()
    return vec

# fusion 
def fuse_probs(image_probs: np.ndarray, audio_prior: np.ndarray, alpha: float = 0.7) -> np.ndarray:
  
    p_img = image_probs / (image_probs.sum() + 1e-8)   # alpha closer to 1 favors image, 0 favors audio.
    p_aud = audio_prior / (audio_prior.sum() + 1e-8)
    p = alpha * p_img + (1.0 - alpha) * p_aud
    p = p / (p.sum() + 1e-8)
    return p

def top1_label_from_probs(p: np.ndarray) -> str:
    return LABELS[int(p.argmax())]
