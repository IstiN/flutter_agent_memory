import 'dart:js_interop';

/// Minimal JS interop for `@mlc-ai/web-llm` loaded from CDN.
///
/// The host page must expose the library on `window.webllm`, e.g.:
///   import * as webllm from 'https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm@0.2.81/+esm';
///   window.webllm = webllm;
///
/// Only the surface needed for the demo is wrapped: engine creation,
/// model reload, chat completion, and progress callbacks.

@JS('webllm.MLCEngine')
extension type WebLlmEngine._(JSObject _) implements JSObject {
  external factory WebLlmEngine(WebLlmEngineConfig config);

  external JSPromise reload(JSString modelId, JSAny? chatConfig);

  external JSPromise chatCompletion(JSObject request);

  external void setInitProgressCallback(JSFunction callback);

  external JSPromise interruptGenerate();
}

@JS('webllm.CreateMLCEngine')
external JSPromise<WebLlmEngine> createMLCEngine(
  JSString modelId,
  JSAny? engineConfig,
  JSAny? chatConfig,
);

@JS()
@anonymous
@staticInterop
class WebLlmEngineConfig {
  external factory WebLlmEngineConfig({
    JSObject? appConfig,
    JSBoolean? useWebWorker,
    JSString? logLevel,
  });
}

/// Prebuilt app config exposed by the CDN build (`window.webllm.prebuiltAppConfig`).
@JS('webllm.prebuiltAppConfig')
external JSObject? get prebuiltAppConfig;

/// Helper installed by [demo/web/index.html] that drains a JS async iterator
/// into a plain array. Dart's JS interop cannot iterate async iterables
/// directly without unsafe reflection, so we use a tiny JS wrapper.
@JS('webllmStreamToArray')
external JSPromise<JSArray<JSObject>> webllmStreamToArray(JSObject asyncIterable);

/// Returns whether a model's weights are already cached by the browser.
@JS('webllmIsModelCached')
external JSPromise<JSBoolean> webllmIsModelCached(JSString modelId);

/// Returns the current download progress for a model (0–1) or null if not found.
@JS('webllmModelProgress')
external JSPromise<JSNumber?> webllmModelProgress(JSString modelId);

/// Deletes a model from the browser's CacheStorage.
@JS('webllmDeleteModel')
external JSPromise<JSAny> webllmDeleteModel(JSString modelId);

/// A progress report from `setInitProgressCallback`.
extension type WebLlmProgressReport._(JSObject _) implements JSObject {
  external JSNumber? get progress;
  external JSString? get text;
  external JSNumber? get timeElapsed;
}
