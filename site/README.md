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
