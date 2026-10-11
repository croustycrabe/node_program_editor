# Web deployment on Cloudflare Pages

The showcase (`example/`) is a web-first Flutter app. These steps also apply
to your own app.

## Build

```bash
cd example
flutter build web --wasm --release --no-web-resources-cdn
```

- `--wasm` compiles to WebAssembly and uses the skwasm renderer, with an
  automatic fallback to the JavaScript build + CanvasKit on browsers without
  WasmGC.
- `--no-web-resources-cdn` puts CanvasKit / skwasm in `build/web` instead of
  loading them from Google's CDN.
- To serve from a sub-path, add `--base-href /editor/`.

The output is `example/build/web`. It already contains `_headers` (copied from
`example/web/_headers`):

```
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: credentialless
  ...
/canvaskit/*
  Cache-Control: public, max-age=31536000, immutable
```

Cross-origin isolation (COOP + COEP) enables multi-threaded skwasm rendering.
`credentialless` keeps third-party resources such as fallback fonts loading.
Use `require-corp` if every resource you load sends a
`Cross-Origin-Resource-Policy` header.

## Option A: direct upload with Wrangler

```bash
npm install -g wrangler
wrangler login
wrangler pages project create node-editor-showcase
wrangler pages deploy example/build/web --project-name node-editor-showcase
```

## Option B: Git integration

Cloudflare Pages has no Flutter preset; install the SDK in the build command:

| Setting | Value |
|---|---|
| Framework preset | None |
| Build command | `git clone https://github.com/flutter/flutter.git -b stable --depth 1 /tmp/flutter && /tmp/flutter/bin/flutter config --enable-web && cd example && /tmp/flutter/bin/flutter build web --wasm --release --no-web-resources-cdn` |
| Build output directory | `example/build/web` |
| Root directory | `/` |

Alternatively, build in GitHub Actions and deploy with the
`cloudflare/wrangler-action`:

```yaml
name: Deploy showcase
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: cd example && flutter build web --wasm --release --no-web-resources-cdn
      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages deploy example/build/web --project-name node-editor-showcase
```

## Custom domain

In the Pages project, choose **Custom domains → Set up a domain** and add, for
example, `editor.yourdomain.com`. If the domain's DNS is already on
Cloudflare, the CNAME record is created for you.

## Checks after deploying

- Open the site and check in DevTools → Console that
  `self.crossOriginIsolated === true` (multi-threaded rendering enabled).
- Network tab: `main.dart.wasm` served with `content-type: application/wasm`
  (Cloudflare does this automatically).
- After a redeploy, `index.html` and `flutter_bootstrap.js` are revalidated
  (`no-cache` in `_headers`), so users get the new version.
