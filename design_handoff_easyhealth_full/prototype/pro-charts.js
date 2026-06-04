/* ============================================================
   EasyHealth Pro — geradores de SVG (sparkline, anel, linha)
   Tudo herda var(--primary) etc. Sem libs externas.
   ============================================================ */
window.EH = window.EH || {};

/* sparkline simples (linha + ponto final) */
EH.sparkline = function (vals, w, h, stroke) {
  w = w || 72; h = h || 36; stroke = stroke || 'var(--primary)';
  var min = Math.min.apply(null, vals), max = Math.max.apply(null, vals);
  var rng = (max - min) || 1, pad = 3;
  var pts = vals.map(function (v, i) {
    var x = pad + (i / (vals.length - 1)) * (w - pad * 2);
    var y = h - pad - ((v - min) / rng) * (h - pad * 2);
    return [x, y];
  });
  var d = pts.map(function (p, i) { return (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1); }).join(' ');
  var area = d + ' L' + pts[pts.length - 1][0].toFixed(1) + ' ' + h + ' L' + pts[0][0].toFixed(1) + ' ' + h + ' Z';
  var last = pts[pts.length - 1];
  var id = 'sg' + Math.random().toString(36).slice(2, 7);
  return '<svg viewBox="0 0 ' + w + ' ' + h + '" width="' + w + '" height="' + h + '" fill="none">' +
    '<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="' + stroke + '" stop-opacity="0.28"/>' +
      '<stop offset="1" stop-color="' + stroke + '" stop-opacity="0"/></linearGradient></defs>' +
    '<path d="' + area + '" fill="url(#' + id + ')"/>' +
    '<path d="' + d + '" stroke="' + stroke + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
    '<circle cx="' + last[0].toFixed(1) + '" cy="' + last[1].toFixed(1) + '" r="2.6" fill="' + stroke + '"/></svg>';
};

/* anel de progresso (0–100) */
EH.ring = function (pct, size, sw, color) {
  size = size || 78; sw = sw || 7; color = color || 'var(--primary)';
  var r = (size - sw) / 2, c = 2 * Math.PI * r, off = c * (1 - pct / 100);
  return '<svg viewBox="0 0 ' + size + ' ' + size + '" width="' + size + '" height="' + size + '" style="transform:rotate(-90deg)">' +
    '<circle cx="' + size / 2 + '" cy="' + size / 2 + '" r="' + r + '" fill="none" stroke="var(--bg-2)" stroke-width="' + sw + '"/>' +
    '<circle cx="' + size / 2 + '" cy="' + size / 2 + '" r="' + r + '" fill="none" stroke="' + color + '" stroke-width="' + sw + '" ' +
    'stroke-linecap="round" stroke-dasharray="' + c.toFixed(1) + '" stroke-dashoffset="' + off.toFixed(1) + '"/></svg>';
};

/* linha grande (evolução de carga) com eixo simples */
EH.lineChart = function (vals, w, h) {
  w = w || 320; h = h || 150;
  var min = Math.min.apply(null, vals), max = Math.max.apply(null, vals);
  var rng = (max - min) || 1, padX = 6, padTop = 14, padBot = 18;
  var pts = vals.map(function (v, i) {
    var x = padX + (i / (vals.length - 1)) * (w - padX * 2);
    var y = padTop + (1 - (v - min) / rng) * (h - padTop - padBot);
    return [x, y];
  });
  var d = pts.map(function (p, i) { return (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1); }).join(' ');
  var area = d + ' L' + pts[pts.length - 1][0].toFixed(1) + ' ' + (h - padBot) + ' L' + pts[0][0].toFixed(1) + ' ' + (h - padBot) + ' Z';
  var id = 'lg' + Math.random().toString(36).slice(2, 7);
  var dots = pts.map(function (p, i) {
    var lastOne = i === pts.length - 1;
    return '<circle cx="' + p[0].toFixed(1) + '" cy="' + p[1].toFixed(1) + '" r="' + (lastOne ? 4.5 : 3) + '" fill="' + (lastOne ? 'var(--primary)' : 'var(--surface)') + '" stroke="var(--primary)" stroke-width="2"/>';
  }).join('');
  // gridlines
  var grid = '';
  for (var g = 0; g < 3; g++) {
    var gy = padTop + (g / 2) * (h - padTop - padBot);
    grid += '<line x1="' + padX + '" y1="' + gy.toFixed(1) + '" x2="' + (w - padX) + '" y2="' + gy.toFixed(1) + '" stroke="var(--border)" stroke-width="1" stroke-dasharray="2 4"/>';
  }
  return '<svg viewBox="0 0 ' + w + ' ' + h + '" width="100%" height="' + h + '" fill="none">' +
    '<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="var(--primary)" stop-opacity="0.3"/>' +
      '<stop offset="1" stop-color="var(--primary)" stop-opacity="0"/></linearGradient></defs>' +
    grid +
    '<path d="' + area + '" fill="url(#' + id + ')"/>' +
    '<path d="' + d + '" stroke="var(--primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>' +
    dots + '</svg>';
};

/* corpo + músculo destacado (mapa) */
EH.bodyMap = function (highlight) {
  var hl = 'oklch(0.70 0.19 28)';
  var parts = {
    peito: '<ellipse cx="30" cy="26" rx="11" ry="7" fill="' + hl + '"/>',
    costas: '<ellipse cx="30" cy="28" rx="11" ry="9" fill="' + hl + '"/>',
    ombro: '<circle cx="19" cy="20" r="4" fill="' + hl + '"/><circle cx="41" cy="20" r="4" fill="' + hl + '"/>',
    perna: '<rect x="22" y="48" width="6" height="22" rx="3" fill="' + hl + '"/><rect x="32" y="48" width="6" height="22" rx="3" fill="' + hl + '"/>',
    core: '<rect x="24" y="34" width="12" height="12" rx="3" fill="' + hl + '"/>',
    'braço': '<rect x="11" y="24" width="5" height="16" rx="2.5" fill="' + hl + '"/><rect x="44" y="24" width="5" height="16" rx="2.5" fill="' + hl + '"/>'
  };
  return '<svg class="body" viewBox="0 0 60 80">' +
    '<path d="M30 4a7 7 0 0 1 7 7c0 3-2 5-2 7l8 4c3 2 4 5 4 9v10c0 2-3 2-3 0l-1-8-2 1v22c0 3-5 3-5 0l-1-15h-8l-1 15c0 3-5 3-5 0V41l-2-1-1 8c0 2-3 2-3 0V38c0-4 1-7 4-9l8-4c0-2-2-4-2-7a7 7 0 0 1 7-7z" fill="var(--surface-3)"/>' +
    (parts[highlight] || '') + '</svg>';
};
