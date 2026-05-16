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

## Updating content

The page is composed in `src/App.tsx` from one component per section
(`Hero`, `Features`, `HowItWorks`, `Contribute`, `Install`, `Footer`).
Copy lives inline in each component so changes are localized.

Keep the site's description of features, classifiers, and install flow
in sync with the app's actual behavior and with the repo `README.md`.
