# devloop site

Minimal static marketing site for the `devloop` CLI. Single page, monochrome
teletype aesthetic, violet accent matching the CLI brand. No runtime
dependencies: Tailwind compiled to static CSS, IBM Plex Mono self-hosted from
`fonts/` (OFL, weights 400 + 700), used across the whole page.

## Develop

```sh
pnpm install
pnpm dev        # tailwind watch -> dist/styles.css
pnpm preview    # build + serve dist/ at http://localhost:4178
```

## Build

```sh
pnpm build      # writes dist/index.html + dist/styles.css
```

`build.mjs` clears `dist/`, compiles `src/input.css` with the Tailwind CLI to
`dist/styles.css`, then copies `index.html` and `fonts/` into `dist/`. The
output is fully static (HTML, CSS, woff2) with no runtime dependency. Deploy the
`dist/` directory to any static host.

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
2. `https://devloop.sh/install` serves the install script as `text/plain`. Until
   the real installer exists, either drop an `install` file into the deployed
   output or add a redirect to the raw `install.sh` in the CLI repo. With Pages,
   a `dist/_redirects` line like `/install https://raw.githubusercontent.com/satyaborg/devloop/main/install.sh 200`
   proxies it.

## Other static hosts

`dist/` is plain static files, so it also drops onto Vercel, Netlify, GitHub
Pages, or S3/CloudFront. Set the build command to `pnpm build` and the publish
directory to `site/dist`.

## Structure

```
site/
  index.html      source page
  src/input.css   tailwind entry + theme tokens + @font-face
  build.mjs       build script (tailwind compile + copy html/fonts)
  fonts/          IBM Plex Mono woff2 (400, 700)
  dist/           build output (gitignored)
```
