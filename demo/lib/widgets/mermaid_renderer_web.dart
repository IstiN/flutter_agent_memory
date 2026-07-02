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
window.famNodeClick = function(id) {
  window.parent.postMessage({source: 'flutter_agent_memory', type: 'mermaid-node-click', id: id}, '*');
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
  let dragStarted = false;
  let startX = 0;
  let startY = 0;
  let lastX = 0;
  let lastY = 0;
  const DRAG_THRESHOLD = 5;
  const MIN_SCALE = 0.15;
  const MAX_SCALE = 6;

  function applyTransform(svg) {
    svg.style.transform = 'translate(' + tx.toFixed(2) + 'px, ' + ty.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ')';
  }

  function resetTransform(svg) {
    scale = 1;
    tx = 0;
    ty = 0;
    applyTransform(svg);
  }

  function setupNodeClicks(svg) {
    svg.querySelectorAll('.node[data-id]').forEach(function(node) {
      node.style.cursor = 'pointer';
      node.addEventListener('click', function(e) {
        e.stopPropagation();
        const id = node.getAttribute('data-id');
        if (id && window.famNodeClick) window.famNodeClick(id);
      });
    });
  }

  function setupZoomPan(svg) {
    svg.style.cursor = 'grab';
    svg.style.transformOrigin = '0 0';
    svg.style.pointerEvents = 'all';
    applyTransform(svg);

    svg.addEventListener('wheel', function(e) {
      e.preventDefault();
      e.stopPropagation();
      const hostRect = svg.parentElement.getBoundingClientRect();
      const x = e.clientX - hostRect.left;
      const y = e.clientY - hostRect.top;
      const delta = e.deltaY || e.detail || 0;
      const zoomFactor = Math.exp(-delta * 0.002);
      const newScale = Math.min(Math.max(scale * zoomFactor, MIN_SCALE), MAX_SCALE);
      const ratio = newScale / scale;
      tx = x - (x - tx) * ratio;
      ty = y - (y - ty) * ratio;
      scale = newScale;
      applyTransform(svg);
    }, { passive: false, capture: true });

    svg.addEventListener('pointerdown', function(e) {
      if (e.button !== 0) return;
      // Let real clicks on nodes open record details; don't start a pan on a node.
      if (e.target.closest('.node')) return;
      dragging = true;
      dragStarted = false;
      startX = e.clientX;
      startY = e.clientY;
      lastX = e.clientX;
      lastY = e.clientY;
      svg.style.cursor = 'grabbing';
      try { svg.setPointerCapture(e.pointerId); } catch (_) {}
    });

    svg.addEventListener('pointermove', function(e) {
      if (!dragging) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!dragStarted && Math.sqrt(dx * dx + dy * dy) < DRAG_THRESHOLD) {
        return;
      }
      if (!dragStarted) {
        dragStarted = true;
      }
      const moveX = e.clientX - lastX;
      const moveY = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      tx += moveX / scale;
      ty += moveY / scale;
      applyTransform(svg);
    });

    function endDrag(e) {
      dragging = false;
      dragStarted = false;
      svg.style.cursor = 'grab';
      if (e && e.pointerId != null) {
        try { svg.releasePointerCapture(e.pointerId); } catch (_) {}
      }
    }

    svg.addEventListener('pointerup', function(e) { endDrag(e); });
    svg.addEventListener('pointercancel', function(e) { endDrag(e); });
    svg.addEventListener('pointerleave', function(e) { if (dragging) endDrag(e); });

    svg.addEventListener('dblclick', function(e) {
      e.stopPropagation();
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
    element.setAttribute('data-diagram', diagram);
    element.innerHTML = '';
    mermaid.render('mermaid-svg-' + Date.now(), diagram)
      .then(({ svg }) => {
        element.innerHTML = svg;
        const svgEl = element.querySelector('svg');
        if (svgEl) {
          svgEl.style.width = '100%';
          svgEl.style.height = '100%';
          svgEl.style.display = 'block';
          setupNodeClicks(svgEl);
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
        fontFamily: 'ui-sans-serif, system-ui, sans-serif',
        fontSize: '14px'
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
