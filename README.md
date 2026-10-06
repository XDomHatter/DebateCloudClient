# debate_cloud

DebateCloud mobile app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Server address

The app talks to the DebateCloud server over HTTP (port 8000 by default) and
WebSocket (`/ws/chat`). The address is resolved by `lib/app/server_settings.dart`,
in priority order:

1. the value the user typed in the server dialog (persisted in
   `SharedPreferences`);
2. the compile-time default injected at build time:
   `--dart-define=SERVER_IP=... --dart-define=SERVER_PORT=...`;
3. the built-in fallback `http://127.0.0.1:8000`.

**Where to change it.** The entry is deliberately on the framework, not inside
page content: when the server is unreachable, pages render as error states and
an entry living in page content would vanish exactly when it is needed. It is
reachable from

- the login page (gear icon in the AppBar);
- the sidebar navigation, as a 「服务器」item at the bottom (tablet/desktop);
- the AppBar of content pages — `AppPageScaffold` adds it automatically, so
  pages using it inherit the entry for free (`showServerAction: false` opts
  out; a page passing its own `appBar:` must add `AppServerAction` itself).

Release packages should still inject the dart-define values so a fresh install
ships with the right address — without them a phone would point at
`127.0.0.1`, i.e. at itself:

```sh
flutter build apk --dart-define=SERVER_IP=203.0.113.10 --dart-define=SERVER_PORT=8000
```

`SERVER_IP` may be a bare host (`192.168.1.10`), a `host:port` pair, or a URL
with a scheme (`https://dc.example.com`). Without an explicit port, `https`
falls back to 443 and everything else to 8000; `https` also switches the
WebSocket to `wss`.

Changing the address at runtime has two side effects worth knowing: the
WebSocket is rebuilt against the new host, and if a user was logged in the
session is dropped, because a JWT issued by one server is always rejected by
another. (If the new address still accepts the current token — e.g. only the
port changed — the session is kept; if the new address is simply unreachable,
the session is left alone.)

### Platform notes

Allowing an arbitrary address means plain HTTP over the LAN, which mobile and
desktop platforms lock down by default:

- **Android** — `android:usesCleartextTraffic="true"` is already set in
  `android/app/src/main/AndroidManifest.xml`.
- **iOS / macOS** — `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` is
  enabled in `Info.plist`. If you ship against one fixed `https` host, narrow
  this back down to an `NSExceptionDomains` allow-list; it cannot be narrowed
  while the address stays user-supplied.
- **Web** — cross-origin browser calls need CORS headers from the server.
  The server sends them by default (any origin); pass
  `--cors-origin <origin>[,<origin>...]` to restrict to specific origins.
  Serving the built `build/web` from the same origin as the API (same-domain
  deployment behind one reverse proxy) needs no CORS at all.

### Running the built web artifact

`flutter build web --release` produces a self-contained static site in
`build/web`. Serve that directory as the web root with any static file
server and open it over HTTP:

```sh
cd build/web && python -m http.server 8123
# → http://127.0.0.1:8123/
```

- The directory **must** be the server root. Serving a parent directory and
  opening `/build/web/…` as a sub-path breaks everything (`<base href="/">`
  makes the browser fetch assets from the root, which then 404s → white
  page). Opening `index.html` via `file://` fails the same way.
- Do not ship a `--wasm` build: its output requires WasmGC + WebGL2 on a
  Blink-family browser and ships no JS fallback, so every other browser gets
  a blank page. The plain JS build runs anywhere.
- The rendering engine (canvaskit) is loaded from the bundled `canvaskit/`
  directory (`canvasKitBaseUrl` in `web/index.html`), not from the
  gstatic CDN — the artifact works on networks where Google CDN is
  unreachable. App fonts still come from fonts.gstatic.com; when that is
  unreachable the UI falls back to system fonts (cosmetic only).
- `.wasm` must be served as `application/wasm`, or the engine fails to
  compile and the page stays blank with
  `TypeError: Failed to execute 'compile' on 'WebAssembly': Incorrect
  response MIME type`. Older Pythons / distro mime tables don't know the
  type (`curl -sI http://host:port/canvaskit/chromium/canvaskit.wasm` to
  check). Patch `python -m http.server` with
  `mimetypes.add_type('application/wasm', '.wasm')` before starting it, or
  use Caddy/nginx (nginx ≥ 1.21.4) which ship the mapping.
