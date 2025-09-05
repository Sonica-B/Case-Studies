import numpy as np
def test_concat_dim():
    img, aud = np.random.randn(512), np.random.randn(768)
    assert (img.size + aud.size) == 1280
