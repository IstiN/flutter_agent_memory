# demo

Flutter web demo for the on-device Gemma memory assistant.

## Running

```bash
cd demo
flutter run -d chrome
```

## macOS builds

The macOS app is signed ad-hoc by default so it builds without an Apple
Developer certificate. Ad-hoc signed apps do not reliably trigger macOS privacy
prompts (Calendar, Contacts, HealthKit, HomeKit) and may not appear in System
Settings.

Use the helper scripts to sign with a local Apple Development certificate
automatically:

```bash
cd demo
./scripts/run_macos.sh           # debug run, signed if a cert is available
./scripts/build_macos.sh --release
./scripts/build_macos_nosandbox.sh
```

To force a specific identity or team:

```bash
FA_CODE_SIGN_IDENTITY='Apple Development' FA_DEVELOPMENT_TEAM='YOUR_TEAM' \
  ./scripts/build_macos.sh --release
```

## Real integration tests

- **HuggingFace preset URLs**: `HUGGINGFACE_TOKEN=hf_xxx flutter test test/integration/huggingface_presets_test.dart`
- **On-device inference smoke test**: build with `lib/main_smoke.dart` and open in a browser with WebGPU/WebGL support.
