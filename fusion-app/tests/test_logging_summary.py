from pathlib import Path
import sys


sys.path.insert(0, str(Path(__file__).parent.parent))

from utils_media import append_csv, summarize_csv, now_iso

def test_append_and_summarize(tmp_path: Path):
    csv_path = tmp_path / "runs_local.csv"
    # two mock rows
    append_csv(csv_path, {
        "ts": now_iso(), "engine": "local", "mode": "video", "alpha": 0.7,
        "t_image_ms": 100, "t_audio_ms": 50, "t_fuse_ms": 10, "t_total_ms": 170,
        "pred": "calm", "probs": {"calm":0.6}
    })
    append_csv(csv_path, {
        "ts": now_iso(), "engine": "local", "mode": "image_audio", "alpha": 0.7,
        "t_image_ms": 200, "t_audio_ms": 60, "t_fuse_ms": 12, "t_total_ms": 272,
        "pred": "joyful", "probs": {"joyful":0.55}
    })
    stats = summarize_csv(csv_path)
    assert stats["t_total_ms"]["n"] == 2
    assert 170.0 <= stats["t_total_ms"]["p50"] <= 272.0
    assert stats["t_image_ms"]["p95"] >= stats["t_image_ms"]["p50"]
