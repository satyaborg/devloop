# devloop site

Minimal static landing site for the `devloop` CLI. Single page, monochrome
teletype aesthetic, violet accent matching the CLI brand. No runtime
dependencies: Tailwind compiled to static CSS, JetBrains Mono self-hosted from
`public/fonts/` (OFL, weights 400 + 700), used across the whole page. Built with
Vite, so dev is just two commands.

## Develop

```sh
pnpm install
pnpm dev        # vite dev server with HMR at http://localhost:5173
pnpm preview    # serve the production build at http://localhost:4178
```

## Build

```sh
pnpm build      # vite build -> dist/
```

Vite compiles `src/input.css` (Tailwind v4 via `@tailwindcss/vite`), hashes the
CSS, inlines the `<link>` into `index.html`, and copies `public/` (the fonts)
into `dist/`. The output is fully static (HTML, CSS, woff2) with no runtime
dependency. Deploy the `dist/` directory to any static host.

## Deploy to Cloudflare Pages

### Option A: Git integration (recommended)

In the Cloudflare dashboard, Workers & Pages > Create > Pages > Connect to Git,
pick this repo, and set:

- Production branch: `main`
- Root directory: `site`
- Build command: `pnpm build`
- Build output directory: `dist` (relative to the root directory, i.e. `site/dist`)

Every push to `main` then rebuilds and deploys. Preview deployments are created
for other branches automatically.

### Option B: Direct upload with Wrangler

```sh
cd site
pnpm install
pnpm build
npx wrangler pages deploy dist --project-name devloop
```

### Custom domain (devloop.sh)

The install command on the page is `curl -fsSL https://devloop.sh/install | bash`,
so deployment is only complete once two things are true:

1. `devloop.sh` points at this Pages project (Pages project > Custom domains >
   add `devloop.sh`; Cloudflare provisions the TLS cert).
2. `https://devloop.sh/install` serves `public/install`, a small bootstrap that
   reads `public/VERSION` from `https://devloop.sh/VERSION` and executes the
   installer from the matching Git tag.

For releases, push the Git tag and confirm Pages has deployed the release
commit. A stale Pages deploy keeps new installs on the previous version, while a
`VERSION` file that points at an unpushed tag makes `/install` fail when it
fetches the tagged installer.

## Other static hosts

`dist/` is plain static files, so it also drops onto Vercel, Netlify, GitHub
Pages, or S3/CloudFront. Set the build command to `pnpm build` and the publish
directory to `site/dist`.

## Structure

```
site/
  index.html         source page (vite entry)
  src/input.css      tailwind entry + theme tokens + @font-face
  vite.config.js     vite + @tailwindcss/vite plugin
  public/_headers    Cloudflare Pages headers for extensionless files
  public/install     VERSION-based bootstrap served at /install
  public/VERSION     release version served at /VERSION
  public/fonts/      JetBrains Mono woff2 (400, 700), served at /fonts/
  dist/              build output (gitignored)
```
