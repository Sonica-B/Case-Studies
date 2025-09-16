import numpy as np
import importlib

fusion = importlib.import_module("fusion")

def test_fuse_probs_is_distribution_and_shape():
    K = len(fusion.LABELS)
    p_img = np.array([0.6, 0.4] + [0]*(K-2), dtype=float)
    p_aud = np.array([0, 0.2, 0.8] + [0]*(K-3), dtype=float)
    out = fusion.fuse_probs(p_img, p_aud, alpha=0.75)
    assert out.shape == (K,)
    assert np.all(out >= 0)
    assert np.isclose(out.sum(), 1.0, atol=1e-6)

def test_alpha_shifts_mass_toward_image_or_audio():
    K = len(fusion.LABELS)
    e_img = np.zeros(K); e_img[0] = 1.0  # image wants class 0
    e_aud = np.zeros(K); e_aud[1] = 1.0  # audio wants class 1
    hi = fusion.fuse_probs(e_img, e_aud, alpha=0.9)
    lo = fusion.fuse_probs(e_img, e_aud, alpha=0.1)
    assert hi[0] > lo[0]   # image favored when alpha high
    assert lo[1] > hi[1]   # audio favored when alpha low
    assert hi[0] > hi[1]   # image still wins when alpha high
    assert lo[1] > lo[0]   # audio still wins when alpha low