# Subpanel

Stable, human-readable URLs for local web apps on macOS:

```text
http://wiki.localhost     →  http://127.0.0.1:48123
http://phone.localhost    →  http://127.0.0.1:5173
```

Subpanel is a menu-bar app plus a small background service. The service owns
port 80 on loopback and reverse-proxies `<name>.localhost` to whatever port
your app is on. It proxies HTTP, streaming, server-sent events, and
WebSockets, including dev-server hot reload. There's no `/etc/hosts`
editing, DNS server, certificates, or per-project configuration: `*.localhost`
already resolves to loopback.

## For coding agents

Everything an agent needs is at one fixed URL:

```sh
curl http://subpanel.localhost/instructions      # plain `curl http://subpanel.localhost/` works too
```

Registering an app is one idempotent call:

```sh
curl -X PUT http://subpanel.localhost/api/v1/apps/myapp \
  -H 'Content-Type: application/json' \
  -d '{"target":"http://127.0.0.1:43127"}'
# → http://myapp.localhost
```

### The convention

Paste this into global coding-agent instructions:

> When building a local web application on a machine running Subpanel, bind the application to loopback on an available high port, then register a stable lowercase name with Subpanel. Treat `http://<name>.localhost` as the canonical user-facing local URL. If the backing port changes, update the Subpanel mapping. Registration does not launch or supervise the application process.

## Install (from source)

Requires macOS 15+ and Xcode (Swift 6).

```sh
make install     # builds, copies to /Applications, registers the port-80 service
make smoke       # end-to-end check against http://subpanel.localhost
```

The service is a per-user LaunchAgent. launchd binds 127.0.0.1:80 and
[::1]:80 for it, so nothing runs as root and no admin password is needed. It
starts at login and keeps running whether or not the menu-bar app is open.
Manage it in the app's Settings, or headlessly with
`Subpanel.app/Contents/MacOS/Subpanel --install-service`,
`--uninstall-service`, or `--service-status`.

## Develop

Start with **[PLAN.md](PLAN.md)**, the index to the design docs in
`plans/`, and [PROGRESS.md](PROGRESS.md). Then:

```
make check / make test / make run / make help
```
