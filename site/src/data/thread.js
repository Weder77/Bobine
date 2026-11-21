// The thread, section by section, in % of each section (x across, y down).
// A stretch ends where the next one starts (x at y = 100 → x at y = 0), so the
// thread runs unbroken down the page. On a wide screen it weaves through the
// margins and under the cards; on a phone it runs down the right gutter.

const gutter = 'M97 0 C 98 35, 96 70, 97 100';

export const threads = {
  // From the bottom of the spool (centre) out to the right margin.
  hero: { wide: 'M50 0 C50 7, 88 3, 95 12 C 99 18, 96 40, 96 60 C 96 80, 94 92, 95 100', phone: 'M50 0 C 50 6, 90 3, 97 10 C 99 14, 97 60, 97 100' },
  shot: { wide: 'M95 0 C 97 25, 93 50, 96 75 C 98 88, 95 95, 95 100', phone: gutter },
  use: { wide: 'M95 0 C 96 22, 70 34, 45 46 C 22 57, 18 76, 45 86 C 70 94, 95 92, 95 100', phone: gutter },
  dl: { wide: 'M95 0 C 95 30, 70 45, 50 55 C 30 65, 6 70, 5 100', phone: gutter },
  // A loop in the left margin, then across under the cards.
  feat: { wide: 'M5 0 C 3 20, 7 30, 5 42 C 3 52, 9 56, 8 50 C 7 44, 2 46, 4 54 C 6 66, 30 80, 60 88 C 80 94, 95 96, 95 100', phone: gutter },
  tv: { wide: 'M95 0 C 97 30, 93 60, 96 80 C 97 90, 95 96, 95 100', phone: gutter },
  acc: { wide: 'M95 0 C 95 30, 80 50, 65 66 C 55 78, 50 88, 50 100', phone: gutter },
  // A last curl, ending on the knot (at 85 % of its 160 px).
  end: { wide: 'M50 0 C 50 30, 46 40, 47 56 C 48 70, 54 68, 53 58 C 52 48, 46 58, 48 70 C 49 78, 50 82, 50 85', phone: 'M97 0 C 97 30, 70 40, 56 58 C 51 66, 50 78, 50 85' },
};
