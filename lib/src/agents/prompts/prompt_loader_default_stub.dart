/// Default prompt loader is unavailable on the web.
///
/// Use [PromptLoader.setLoader] to inject a host-provided loader
/// (e.g. Flutter `rootBundle`) before calling any agent.
Future<String> loadPromptFile(String name) async {
  throw UnsupportedError(
    'Default prompt loader is not available on web. '
    'Call PromptLoader.setLoader(...) at startup.',
  );
}
