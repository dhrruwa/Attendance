# Drop-in model slot

Place the two on-device model files here. The app loads them at startup; if a
file is missing it falls back to a documented **stub** scorer (and tags
`face_model_version: "stub"` in the evidence) so the app still runs end-to-end.

| File | Purpose | Suggested source |
|------|---------|------------------|
| `mobilefacenet.tflite` | 112×112 RGB → 192-d face embedding (cosine-matched against the enrolled template) | MobileFaceNet TFLite (e.g. sirius-ai/MobileFaceNet_TF export, or the model bundled with shubham0204's OnDevice-Face-Recognition repo) |
| `antispoof.tflite` | Passive anti-spoofing score (live vs photo/replay) | MiniFASNet-V2 from MiniVision's Silent-Face-Anti-Spoofing, converted to TFLite |

Input/output tensor shapes the loaders expect are documented in
`lib/face/face_matcher.dart` and `lib/face/spoof_detector.dart`. If your model
differs, adjust the pre/post-processing there.

> These binaries are intentionally **not** committed (see root `.gitignore`).
