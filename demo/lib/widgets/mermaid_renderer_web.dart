// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html';
import 'dart:ui_web' as ui_web;

void platformRender(String diagram, String viewType) {
  final escaped = diagram
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final wrapper = DivElement()
      ..style.width = '100%'
      ..style.height = '100%';

    final script = ScriptElement()
      ..type = 'module'
      ..text = '''
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });
const graph = `$escaped`;
const element = document.getElementById('mermaid-\$viewId');
mermaid.render('svg-\$viewId', graph).then(({ svg }) => {
  element.innerHTML = svg;
}).catch(err => {
  element.innerHTML = '<pre style="color:red">' + err.toString() + '</pre>';
});
''';
    final container = PreElement()
      ..id = 'mermaid-$viewId'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.margin = '0'
      ..style.overflow = 'auto'
      ..text = diagram;

    wrapper.append(container);
    wrapper.append(script);
    return wrapper;
  });
}
