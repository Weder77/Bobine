// The landing page's thread: each section's stretch is drawn down to 62 % of
// the window as the page scrolls, the big spool turns and empties, and so
// does the little one in the header (always in view: it shows how far the
// page has gone). With "reduce motion", or a page that does not scroll, the
// thread is simply all there and the spools stay still.

const NARROW = 760;
const REVEAL = 0.62;

const clamp = (v) => Math.max(0, Math.min(1, v));

export function startThread() {
  const root = document.querySelector('[data-bobine-page]');
  if (!root) return;
  const threads = [...root.querySelectorAll('svg[data-thread]')];
  const knot = root.querySelector('.knot');
  const part = (name) => root.querySelector(`[data-spool="${name}"]`);
  const spool = { body: part('body'), clip: part('clip'), stripes: part('stripes'), tail: part('tail') };
  const mini = { body: part('mini-body'), clip: part('mini-clip'), stripes: part('mini-stripes') };
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');

  let narrow = null;
  let frame = 0;

  function setPaths() {
    const now = window.innerWidth < NARROW;
    if (now === narrow) return;
    narrow = now;
    for (const svg of threads) {
      const path = svg.querySelector('path');
      path.setAttribute('d', narrow ? path.dataset.phone : path.dataset.wide);
    }
  }

  // p: how far the page has gone (0 → 1); scrolled: pixels, for the turning.
  function setSpools(p, scrolled) {
    if (spool.body) {
      const w = 124 - 80 * p;
      const x = 100 - w / 2;
      for (const el of [spool.body, spool.clip]) {
        el.setAttribute('x', x.toFixed(1));
        el.setAttribute('width', w.toFixed(1));
      }
      spool.stripes.setAttribute('transform', `translate(0 ${((scrolled * 0.35) % 28).toFixed(1)})`);
      const edge = x + w - 1;
      spool.tail.setAttribute('d', `M${edge.toFixed(1)} 150 C ${(edge + 38).toFixed(1)} 160, 204 232, 168 262 C 140 284, 106 290, 100 300`);
    }
    if (mini.body && mini.clip) {
      const w = 16 - 10 * p;
      for (const el of [mini.body, mini.clip]) {
        el.setAttribute('x', (11 - w / 2).toFixed(2));
        el.setAttribute('width', w.toFixed(2));
      }
      mini.stripes?.setAttribute('transform', `translate(0 ${((scrolled * 0.12) % 8).toFixed(2)})`);
    }
  }

  function update() {
    frame = 0;
    setPaths();
    const vh = window.innerHeight || 1;
    const page = root.getBoundingClientRect();
    const still = motion.matches || page.height <= vh + 8;
    let end = 1;
    for (const svg of threads) {
      const box = svg.getBoundingClientRect();
      const drawn = still ? 1 : clamp((vh * REVEAL - box.top) / (box.height || 1));
      svg.style.clipPath = `inset(0 0 ${((1 - drawn) * 100).toFixed(2)}% 0)`;
      if (svg.dataset.thread === 'end') end = drawn;
    }
    knot?.classList.toggle('is-hidden', end <= 0.82);
    const scrolled = Math.max(0, -page.top);
    setSpools(still ? 0 : clamp(scrolled / Math.max(1, page.height - vh)), still ? 0 : scrolled);
  }

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  motion.addEventListener('change', schedule);
  // Fonts and images change the heights once loaded.
  window.addEventListener('load', schedule);
  update();
}
