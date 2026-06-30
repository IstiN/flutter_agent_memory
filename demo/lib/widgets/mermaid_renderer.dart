import 'mermaid_renderer_stub.dart'
    if (dart.library.html) 'mermaid_renderer_web.dart';

abstract class MermaidRenderer {
  static void render(String diagram, String viewType) =>
      platformRender(diagram, viewType);
}
