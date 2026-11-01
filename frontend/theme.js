// Day / night mode. Loaded first in <head>, so the right colours are set before the page is drawn (no white flash).
// Until the person chooses, the page follows the system setting; their choice is remembered in this browser.
(function () {
  'use strict';
  var KEY = 'tt-theme';
  var root = document.documentElement;
  var query = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  // browsers can refuse storage (private windows, blocked site data), so every use is guarded
  function stored() {
    try { var v = localStorage.getItem(KEY); return v === 'light' || v === 'dark' ? v : null; } catch (e) { return null; }
  }
  function remember(v) { try { localStorage.setItem(KEY, v); } catch (e) { /* the choice just lasts until the page closes */ } }
  function system() { return query && query.matches ? 'dark' : 'light'; }

  function paint() {
    var night = root.getAttribute('data-theme') === 'dark';
    var button = document.getElementById('theme');
    if (!button) return;
    // the button names what a click will switch TO
    button.textContent = night ? '☀ Day mode' : '☾ Night mode';
    button.setAttribute('aria-label', night ? 'Switch to day mode' : 'Switch to night mode');
    button.setAttribute('aria-pressed', night ? 'true' : 'false');
  }
  function apply(theme) {
    root.setAttribute('data-theme', theme);
    paint();
  }

  apply(stored() || system());

  document.addEventListener('DOMContentLoaded', function () {
    var button = document.getElementById('theme');
    if (button) button.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      remember(next);
      apply(next);
    });
    paint();
  });

  // while no choice has been made, follow the system when it changes (for example sunset schedules)
  if (query && query.addEventListener) {
    query.addEventListener('change', function () { if (!stored()) apply(system()); });
  }
})();
