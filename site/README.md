# Total Recall website

Marketing site for Total Recall, deployed to GitHub Pages at
<https://alecf.github.io/totalrecall/>. Also hosts the Sparkle appcast
feed (`public/appcast.xml`) that released builds poll for auto-updates.

Built with React + Vite + TypeScript. Component styles use CSS Modules.

## Develop

```bash
cd site
npm install
npm run dev      # local dev server with HMR
npm run build    # type-check + production build to dist/
npm run lint     # ESLint
```

## Deploy

A push to `main` that touches `site/` triggers the GitHub Pages workflow
in `.github/workflows/`, which runs `npm run build` and publishes
`site/dist`.

The `site` job in `ci.yml` runs the same `npm ci` and build on every PR, so
a dependency bump that the lockfile cannot resolve fails there rather than
on `main`. When changing dependencies, run `npm ci` locally — not just
`npm run build`, which passes happily against a stale `node_modules`.

## Updating content

The page is composed in `src/App.tsx` from one component per section
(`Hero`, `Features`, `HowItWorks`, `Contribute`, `Install`, `Footer`).
Copy lives inline in each component so changes are localized.

Keep the site's description of features, classifiers, and install flow
in sync with the app's actual behavior and with the repo `README.md`.

## Responsive layout

One breakpoint carries the phone layout: `max-width: 640px`. `global.css`
redefines two tokens there — `--gutter` (the page's horizontal inset, used
by the nav, hero, sections and footer alike) and `--section-padding` — so a
phone narrows every section in one edit rather than four that can drift.
Sections add their own `640px` block only for what the tokens can't reach:
card padding, type scale, stacking. Wider breakpoints (`768px`, `900px`)
exist only where a specific grid runs out of room earlier.

Below `640px` the nav's section links collapse into a disclosure menu. They
are never simply hidden — a marketing page with no navigation is a bug, not
a small-screen layout.

**Long content must not set the page's width.** Flex and grid items default
to a min-content floor, so one unbreakable token — a clone URL, a `nowrap`
chart label, a line of Swift — silently widens the whole document and every
centered section then hangs off the edge of the viewport. `body` has
`overflow-x: hidden`, which hides that symptom rather than fixing it, so it
must never be what keeps the page in the viewport. Each such container
declares how it yields instead:

- `min-width: 0` where the item should shrink and its content ellipsize or
  scroll (`.bar` and `.column` in `MemoryRiver`, `.codeBlock` in
  `Contribute`, `.card` in `Install`).
- A definite `width: 100%` where the container is shrink-to-fit and would
  otherwise size to its own min-content. `min-width: 0` does *not* help
  here: it removes a flex item's automatic minimum but never lowers its
  min-content contribution. This is why `Hero`'s `.content` sets a width.
- `overflow-wrap: anywhere` for a token that should wrap rather than
  scroll. A soft wrap is visual only, so `git clone …` still copies out of
  the page as a single line.
- `overflow-x: auto` only where wrapping would destroy meaning — the Swift
  sample in `Contribute`, whose indentation is the point.

`npm run build` will not catch a regression here. Check the rendered page at
320px and confirm `document.documentElement.scrollWidth` equals its
`clientWidth`.

## Refreshing the screenshots

`src/assets/` holds real captures of the app, not mockups. They come from
the `pr-screenshots` GitHub Release, which `pr-screenshot.yml` refreshes on
every push to every PR — so there is always a current 780×560 capture of the
inspection window without running the app locally:

```bash
gh release download pr-screenshots -p "pr-<number>.png" -D /tmp
```

`main-window.png` is that capture unmodified. `memory-river.png` and
`group-rows.png` are crops of it — rows `32–182` and `198–428` respectively.
Re-crop with any image tool when the UI changes shape, and update the `alt`
text and captions in `Hero.tsx` / `Features.tsx` to match what the new
capture actually shows.
