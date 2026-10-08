// Vyhledávání v příručce (offline, bez serveru): index je v search-index.js (window.TC_SEARCH).
(function () {
  var input = document.getElementById('q'), box = document.getElementById('results');
  if (!input || !box || !window.TC_SEARCH) return;
  var noResults = document.documentElement.lang === 'cs' ? 'Nic nenalezeno.' : 'Nothing found.';
  var active = -1;
  function norm(s) { return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
  var docs = window.TC_SEARCH.map(function (d) { return { t: d.t, u: d.u, x: d.x, nt: norm(d.t), nx: norm(d.x) }; });
  function esc(s) { return s.replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function snippet(d, words) {
    var i = -1;
    for (var k = 0; k < words.length && i < 0; k++) i = d.nx.indexOf(words[k]);
    if (i < 0) return esc(d.x.slice(0, 110));
    var from = Math.max(0, i - 40), s = esc(d.x.slice(from, from + 130));
    return (from > 0 ? '… ' : '') + s + ' …';
  }
  function search() {
    var q = norm(input.value.trim());
    if (!q) { box.hidden = true; return; }
    var words = q.split(/\s+/).filter(Boolean), hits = [];
    docs.forEach(function (d) {
      var score = 0;
      for (var k = 0; k < words.length; k++) {
        var inTitle = d.nt.indexOf(words[k]) >= 0, inText = d.nx.indexOf(words[k]) >= 0;
        if (!inTitle && !inText) { score = -1; break; }
        score += inTitle ? 5 : 1;
      }
      if (score > 0) hits.push({ d: d, score: score });
    });
    hits.sort(function (a, b) { return b.score - a.score; });
    box.innerHTML = hits.length ? hits.slice(0, 8).map(function (h) {
      return '<a href="' + h.d.u + '"><b>' + esc(h.d.t) + '</b><span>' + snippet(h.d, words) + '</span></a>';
    }).join('') : '<div class="none">' + noResults + '</div>';
    box.hidden = false; active = -1;
  }
  input.addEventListener('input', search);
  input.addEventListener('focus', search);
  input.addEventListener('keydown', function (e) {
    var items = box.querySelectorAll('a');
    if (e.key === 'Escape') { box.hidden = true; input.blur(); return; }
    if (!items.length) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      active = (active + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items.forEach(function (a, i) { a.classList.toggle('active', i === active); });
    } else if (e.key === 'Enter') { (items[Math.max(active, 0)]).click(); }
  });
  document.addEventListener('click', function (e) { if (!box.contains(e.target) && e.target !== input) box.hidden = true; });
  document.addEventListener('keydown', function (e) {
    if ((e.key === '/' || (e.key === 'k' && (e.metaKey || e.ctrlKey))) && document.activeElement !== input) { e.preventDefault(); input.focus(); }
  });
})();
