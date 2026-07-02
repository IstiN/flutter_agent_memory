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
        ..style.backgroundColor = '#0B0E14'
        ..style.overflow = 'hidden';

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
(function() {
  let scale = 1;
  let tx = 0;
  let ty = 0;
  let dragging = false;
  let lastX = 0;
  let lastY = 0;

  function applyTransform(svg) {
    svg.style.transform = 'translate(' + tx + 'px, ' + ty + 'px) scale(' + scale + ')';
  }

  function resetTransform(svg) {
    scale = 1;
    tx = 0;
    ty = 0;
    applyTransform(svg);
  }

  function setupZoomPan(svg) {
    svg.style.cursor = 'grab';
    svg.style.transformOrigin = '0 0';
    applyTransform(svg);

    svg.addEventListener('wheel', function(e) {
      e.preventDefault();
      const rect = svg.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      const newScale = Math.min(Math.max(scale * delta, 0.2), 5);
      const ratio = newScale / scale;
      tx = x - (x - tx) * ratio;
      ty = y - (y - ty) * ratio;
      scale = newScale;
      applyTransform(svg);
    }, { passive: false });

    svg.addEventListener('pointerdown', function(e) {
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
      svg.style.cursor = 'grabbing';
      svg.setPointerCapture(e.pointerId);
    });

    svg.addEventListener('pointermove', function(e) {
      if (!dragging) return;
      const dx = e.clientX - lastX;
      const dy = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      tx += dx;
      ty += dy;
      applyTransform(svg);
    });

    svg.addEventListener('pointerup', function(e) {
      dragging = false;
      svg.style.cursor = 'grab';
      svg.releasePointerCapture(e.pointerId);
    });

    svg.addEventListener('pointerleave', function() {
      dragging = false;
      svg.style.cursor = 'grab';
    });

    svg.addEventListener('dblclick', function() {
      resetTransform(svg);
    });
  }

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
          svgEl.style.width = '100%';
          svgEl.style.height = '100%';
          svgEl.style.display = 'block';
          setupZoomPan(svgEl);
        }
      })
      .catch(err => {
        element.innerHTML = '<pre style="color:#EF4444; padding:16px;">' + err.toString() + '</pre>';
      });
  };
})();
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
