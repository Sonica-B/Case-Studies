import csv
import json
from pathlib import Path
from time import time
from typing import Any, Dict, Tuple, Union
import io
import numpy as np
from PIL import Image
import ffmpeg 
import tempfile
from pydub import AudioSegment

#  helpers 
def probe_duration_sec(video_path: str) -> float:
    try:
        meta = ffmpeg.probe(video_path)
        return float(meta.get("format", {}).get("duration", 0.0)) or 0.0
    except Exception:
        return 0.0
    
def _to_path(p: Union[str, dict, Path]) -> str:
    if isinstance(p, dict):
        return p.get("name") or p.get("path") or p.get("data") or ""
    return str(p)

def _audiosegment_float32(seg: AudioSegment) -> np.ndarray:
    seg = seg.set_frame_rate(16000).set_channels(1).set_sample_width(2)  # 16-bit
    samples = np.array(seg.get_array_of_samples(), dtype=np.int16)
    return (samples.astype(np.float32) / 32768.0)

#  public API
def video_to_frames_and_audio(
    video_in,
    target_frames: int = 64,   # aim for this many frames total
    fps_cap: float = 3.0       # never sample faster than this 
    ) -> Tuple[list, np.ndarray, dict]:

    video_path = _to_path(video_in)
    if not video_path:
        raise ValueError("Empty video path")

    dur = probe_duration_sec(video_path)

    if dur <= 0:
        fps = 1.0
    else:
        fps = min(fps_cap, max(1.0 / dur, target_frames / dur))

    frames = []
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        out_pattern = str(td / "frame_%06d.jpg")
        
        (
            ffmpeg
            .input(video_path)
            .output(out_pattern, vf=f"fps={fps}", vsync="vfr", qscale=2)
            .overwrite_output()
            .run(capture_stdout=True, capture_stderr=True)
        )
        for p in sorted(td.glob("frame_*.jpg")):
            frames.append(Image.open(p).convert("RGB"))

    # Full audio track → mono 16 kHz float32
    seg = AudioSegment.from_file(video_path)
    audio16k = _audiosegment_float32(seg)

    meta = {"duration_s": float(dur), "fps_used": float(fps), "n_frames": int(len(frames))}
    return frames, audio16k, meta

def load_audio_16k(audio_path_like) -> np.ndarray:
    path = _to_path(audio_path_like)
    seg = AudioSegment.from_file(path)
    return _audiosegment_float32(seg)


# Logging 
DEFAULT_CSV = Path(__file__).parent / "runs_local.csv"

def now_iso() -> str:
    # UTC-ish wall time string (sufficient for ordering/eyeballing).
    return time.strftime("%Y-%m-%dT%H:%M:%S")

def append_csv(csv_path: Union[str, Path] = DEFAULT_CSV, row: Dict[str, Any] = None) -> None:
    if row is None:
        return
    p = Path(csv_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    is_new = not p.exists()
    safe_row = {k: (json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in row.items()}
    with p.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(safe_row.keys()))
        if is_new:
            w.writeheader()
        w.writerow(safe_row)

def log_inference(
    *,
    engine: str,          # "local" or "api"
    mode: str,            # "video" or "image_audio"
    alpha: float,
    lat: Dict[str, Any],  # expects keys like t_image_ms, t_audio_ms, t_fuse_ms, t_total_ms, rms 
    pred: str,
    probs: Dict[str, float],
    csv_path: Union[str, Path] = DEFAULT_CSV
) -> None:
    
    payload = {
        "ts": now_iso(),
        "engine": engine,
        "mode": mode,
        "alpha": float(alpha),
        "rms": lat.get("rms"),
        "t_image_ms": lat.get("t_image_ms"),
        "t_audio_ms": lat.get("t_audio_ms"),
        "t_fuse_ms":  lat.get("t_fuse_ms"),
        "t_total_ms": lat.get("t_total_ms"),
        "pred": pred,
        "probs": probs,
    }
    append_csv(csv_path, payload)


# Summarizer

def summarize_csv(
    csv_path: Union[str, Path] = DEFAULT_CSV,
    cols = ("t_image_ms", "t_audio_ms", "t_fuse_ms", "t_total_ms")
) -> Dict[str, Dict[str, float]]:
    """
    Compute p50/p95 for latency columns. Returns a dict so you can print or consume it.
    """
    p = Path(csv_path)
    if not p.exists():
        return {}

    with p.open("r", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    def _col_vals(c):
        out = []
        for r in rows:
            v = r.get(c)
            if v is None or v == "":
                continue
            try:
                out.append(float(v))
            except Exception:
                pass
        return np.array(out, dtype=float)

    stats: Dict[str, Dict[str, float]] = {}
    for c in cols:
        arr = _col_vals(c)
        if arr.size == 0:
            stats[c] = {"p50": float("nan"), "p95": float("nan"), "n": 0}
        else:
            stats[c] = {
                "p50": float(np.percentile(arr, 50)),
                "p95": float(np.percentile(arr, 95)),
                "n":   int(arr.size),
            }
    return stats

if __name__ == "__main__":
    # CLI usage: python fusion-app/utils_media.py [csv_path]
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CSV
    s = summarize_csv(path)
    print(f"File: {path}")
    if not s:
        print("No rows found.")
    else:
        for k in ("t_image_ms", "t_audio_ms", "t_fuse_ms", "t_total_ms"):
            if k in s:
                print(f"{k:>11}:  p50={s[k]['p50']:.1f} ms   p95={s[k]['p95']:.1f} ms   n={s[k]['n']}")