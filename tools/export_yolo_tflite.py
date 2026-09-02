"""Export the packaging-symbol YOLOv8 detector to TFLite for on-device use.

The detector in `legal_metrology_ml/layer1_feature_extraction/object_detector.py`
finds FSSAI logo, Veg/Non-Veg mark, ISI mark, recycling symbol and bar codes.
Ultralytics YOLO exports to TFLite natively — this is the one component of the
pipeline that is a genuine neural network.

Prerequisite: a trained `best.pt` (train with `yolo detect train ...` on a
labelled symbol dataset — the repo ships only a heuristic fallback).

Usage:
    python tools/export_yolo_tflite.py --weights runs/detect/train/weights/best.pt \
                                       --out mobile/assets/models/symbol_detector.tflite \
                                       --imgsz 640 --int8
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", required=True, help="Path to trained YOLOv8 .pt weights")
    ap.add_argument("--out", default="mobile/assets/models/symbol_detector.tflite")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--int8", action="store_true",
                    help="Full-integer quantisation (smallest, needs a data.yaml for calibration)")
    ap.add_argument("--data", default=None, help="data.yaml for int8 calibration")
    a = ap.parse_args()

    from ultralytics import YOLO  # imported late so --help works without the dep

    model = YOLO(a.weights)
    kwargs = dict(format="tflite", imgsz=a.imgsz, nms=True)
    if a.int8:
        kwargs["int8"] = True
        if a.data:
            kwargs["data"] = a.data
    exported = model.export(**kwargs)

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(exported, out)
    print(f"Exported {exported} -> {out}")
    print("Class order (embed this in the Flutter app):", model.names)


if __name__ == "__main__":
    main()
