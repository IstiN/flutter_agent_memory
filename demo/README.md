# demo

Flutter web demo for the on-device Gemma memory assistant.

## Running

```bash
cd demo
flutter run -d chrome
```

## Real integration tests

- **HuggingFace preset URLs**: `HUGGINGFACE_TOKEN=hf_xxx flutter test test/integration/huggingface_presets_test.dart`
- **On-device inference smoke test**: build with `lib/main_smoke.dart` and open in a browser with WebGPU/WebGL support.
