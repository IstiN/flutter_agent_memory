// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

/// Registers a single platform view for the Mermaid diagram before runApp.
void registerMermaidPlatformView() {
  ui_web.platformViewRegistry.registerViewFactory(
    'mermaid-diagram',
    (int viewId) {
      final host = html.DivElement()
        ..id = 'mermaid-host'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#0B0E14';

      final stub = html.ScriptElement()
        ..text = '''
window.__mermaid_queue__ = [];
window.__mermaid_loaded__ = false;
window.renderMermaid = function() {
  window.__mermaid_queue__.push(Array.from(arguments));
};
''';

      final script = html.ScriptElement()
        ..type = 'module'
        ..text = '''
window.renderMermaid = (diagram, elementId) => {
  if (!window.__mermaid_loaded__) {
    window.__mermaid_queue__.push([diagram, elementId]);
    return;
  }
  const element = document.getElementById(elementId);
  if (!element) return;
  element.innerHTML = '';
  mermaid.render('mermaid-svg-' + Date.now(), diagram)
    .then(({ svg }) => {
      element.innerHTML = svg;
      const svgEl = element.querySelector('svg');
      if (svgEl) {
        svgEl.style.maxWidth = '100%';
        svgEl.style.height = '100%';
      }
    })
    .catch(err => {
      element.innerHTML = '<pre style="color:#EF4444; padding:16px;">' + err.toString() + '</pre>';
    });
};
import('https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs')
  .then(module => {
    const mermaid = module.default || module;
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
    window.__mermaid_loaded__ = true;
    window.mermaid = mermaid;
    window.__mermaid_queue__.forEach(args => window.renderMermaid(...args));
    window.__mermaid_queue__ = [];
  })
  .catch(err => {
    console.error('Failed to load Mermaid:', err);
  });
''';

      host
        ..append(stub)
        ..append(script);
      return host;
    },
  );
}

/// Renders [diagram] into the registered Mermaid host element.
void renderMermaidDiagram(String diagram) {
  final renderFn = js.context['renderMermaid'];
  final host = html.document.getElementById('mermaid-host');
  if (renderFn != null && host != null) {
    js.context.callMethod('renderMermaid', [diagram, 'mermaid-host']);
  } else {
    Timer(const Duration(milliseconds: 100), () => renderMermaidDiagram(diagram));
  }
}
