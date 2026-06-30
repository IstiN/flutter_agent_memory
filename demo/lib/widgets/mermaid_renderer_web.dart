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
      ..style.height = '100%'
      ..style.backgroundColor = '#0B0E14'
      ..style.color = '#F8FAFC';

    final script = ScriptElement()
      ..type = 'module'
      ..text = '''
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'loose',
  theme: 'dark',
  themeVariables: {
    primaryColor: '#1E293B',
    primaryTextColor: '#F8FAFC',
    primaryBorderColor: '#8B5CF6',
    lineColor: '#A78BFA',
    secondaryColor: '#111827',
    tertiaryColor: '#0F172A',
    fontFamily: 'ui-sans-serif, system-ui, sans-serif'
  }
});
const graph = `$escaped`;
const element = document.getElementById('mermaid-\$viewId');
mermaid.render('svg-\$viewId', graph).then(({ svg }) => {
  element.innerHTML = svg;
  const svgEl = element.querySelector('svg');
  if (svgEl) {
    svgEl.style.maxWidth = '100%';
    svgEl.style.height = '100%';
  }
}).catch(err => {
  element.innerHTML = '<pre style="color:#EF4444; padding:16px;">' + err.toString() + '</pre>';
});
''';
    final container = PreElement()
      ..id = 'mermaid-$viewId'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.margin = '0'
      ..style.padding = '16px'
      ..style.overflow = 'auto'
      ..style.boxSizing = 'border-box';

    wrapper.append(container);
    wrapper.append(script);
    return wrapper;
  });
}
