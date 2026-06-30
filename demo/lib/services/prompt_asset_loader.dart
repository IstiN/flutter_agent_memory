import 'package:flutter/services.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Configures [PromptLoader] to read prompt XML files from Flutter assets.
void initializePromptAssetLoader() {
  PromptLoader.setLoader((name) async {
    final path = 'packages/flutter_agent_memory/src/agents/prompts/$name';
    return rootBundle.loadString(path);
  });
}
