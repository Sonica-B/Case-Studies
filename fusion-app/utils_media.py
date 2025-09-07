from pathlib import Path
from typing import Tuple, Union
import io
import numpy as np
from PIL import Image
import ffmpeg 
from pydub import AudioSegment

#  helpers 
def _to_path(p: Union[str, dict, Path]) -> str:
    if isinstance(p, dict):
        return p.get("name") or p.get("path") or p.get("data") or ""
    return str(p)

def _audiosegment_float32(seg: AudioSegment) -> np.ndarray:
    seg = seg.set_frame_rate(16000).set_channels(1).set_sample_width(2)  # 16-bit
    samples = np.array(seg.get_array_of_samples(), dtype=np.int16)
    return (samples.astype(np.float32) / 32768.0)

#  public API
def video_to_frame_audio(video_in) -> Tuple[Image.Image, np.ndarray]:
    video_path = _to_path(video_in)
    if not video_path:
        raise ValueError("Empty video path")

    try:
        out, _ = (
            ffmpeg
            .input(video_path)
            .output('pipe:', vframes=1, format='image2', vcodec='mjpeg')
            .run(capture_stdout=True, capture_stderr=True)
        )
        frame = Image.open(io.BytesIO(out)).convert("RGB")
    except ffmpeg.Error as e:
        raise RuntimeError(f"ffmpeg frame extract failed: {e.stderr.decode()[:2000]}")

    
    seg = AudioSegment.from_file(video_path)
    audio16k = _audiosegment_float32(seg)
    return frame, audio16k

def load_audio_16k(audio_path_like) -> np.ndarray:
    path = _to_path(audio_path_like)
    seg = AudioSegment.from_file(path)
    return _audiosegment_float32(seg)