import json
from pathlib import Path
import importlib
import sys


sys.path.insert(0, str(Path(__file__).parent.parent))

fusion = importlib.import_module("fusion")

def test_labels_json_present_and_consistent():
    here = Path(__file__).resolve().parents[1] / "fusion-app"
    data = json.loads((here / "labels.json").read_text())
    assert "labels" in data and len(data["labels"]) > 0
    names = [x["name"] for x in data["labels"]]
    prompts = [x["prompt"] for x in data["labels"]]
    assert len(names) == len(fusion.LABELS) == len(prompts)
    assert all(isinstance(n, str) and n for n in names)
    assert all(isinstance(p, str) and p for p in prompts)
    