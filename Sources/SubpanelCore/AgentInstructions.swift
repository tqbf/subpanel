import Foundation

/// The document an agent reads at `http://subpanel.localhost/instructions`
/// (also `/instructions.md`, `/llms.txt`, and `/` for non-browser clients).
///
/// This is the product's front door for coding agents that know nothing about
/// Subpanel. The first screenful must be enough to act correctly; everything
/// after "Rules" is reference. Keep it in sync with plans/api.md.
public enum AgentInstructions {
    /// The convention paragraph, verbatim — also in README.md, and meant to be
    /// pasted into global coding-agent instructions.
    public static let convention = """
        When building a local web application on a machine running Subpanel, bind the application to \
        loopback on an available high port, then register a stable lowercase name with Subpanel. Treat \
        `http://<name>.localhost` as the canonical user-facing local URL. If the backing port changes, \
        update the Subpanel mapping. Registration does not launch or supervise the application process.
        """

    /// The instructions, with URLs for a proxy on `port` (80 in production).
    public static func markdown(port: Int = SubpanelConstants.proxyPort) -> String {
        let base = SubpanelConstants.controlBaseURL(port: port)
        let api = "\(base)/api/v1"
        let myapp = SubpanelConstants.appURL(name: "myapp", port: port)
        return """
            # Subpanel: stable local URLs for web apps

            Subpanel is running on this machine. It gives each local web app a stable URL like \
            `\(myapp)` and proxies it to a port on loopback. There's nothing to configure: no \
            `/etc/hosts`, no DNS, no certificates.

            API version \(SubpanelConstants.apiVersion). Capabilities: \(base)/.well-known/subpanel

            ## Give your app a URL

            1. Start your app on `127.0.0.1`, on any free high port (say 43127).
            2. Pick a name: lowercase letters, digits, and hyphens, e.g. `myapp`.
            3. Register it:

            ```sh
            curl -sS -X PUT \(api)/apps/myapp \\
              -H 'Content-Type: application/json' \\
              -d '{"target":"http://127.0.0.1:43127"}'
            ```

            4. Use `\(myapp)` as the app's URL everywhere: when you tell the user, in READMEs, and \
            in logs.

            PUT is idempotent and takes effect immediately. Run it again whenever you start the \
            server. If the port has changed, the PUT updates the mapping, so you never need to \
            check first.

            To remove an app for good:

            ```sh
            curl -sS -X DELETE \(api)/apps/myapp
            ```

            ## Rules

            - Don't bind your app to port 80. Subpanel owns it.
            - Don't edit `/etc/hosts`. `*.localhost` already resolves to loopback.
            - Don't bind to `0.0.0.0` unless the user explicitly asks for LAN access.
            - Register only a loopback HTTP port. HTTPS and non-loopback targets are rejected.
            - If the backing port changes, PUT the new target right away.
            - DELETE the mapping when a project is removed for good. Stopping a server for the day \
            isn't a reason to delete it.
            - Subpanel only routes traffic. It doesn't start, restart, or supervise your app. If \
            the process stops, the URL returns 502 until it's back.

            ## The convention

            Paste this into global agent instructions if you want every project to follow it:

            > \(convention)

            ## Picking a port

            Any free port above 1024 works. To get one that's free right now:

            ```sh
            python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'
            ```

            Better still, if your framework can bind port 0, let it choose and register the port \
            it reports. Subpanel has no port allocator, on purpose.

            Examples of binding to loopback:

            - Vite: `vite --host 127.0.0.1 --port 43127 --strictPort`
            - Next.js: `next dev -H 127.0.0.1 -p 43127`
            - Python: `python3 -m http.server 43127 --bind 127.0.0.1`
            - Uvicorn: `uvicorn app:app --host 127.0.0.1 --port 43127`

            Many Node dev servers bind `localhost` to IPv6 `::1` only. If you're not sure which \
            address the server bound, register `http://localhost:PORT`. Subpanel tries `::1`, then \
            `127.0.0.1`.

            ## API reference

            Base URL: \(api). It takes and returns JSON. There's no authentication: any local \
            process may call it. There's no CORS either, so web pages can't.

            - `GET /api/v1/apps`: list all mappings, as `{"apps": [APP, ...]}`
            - `GET /api/v1/apps/NAME`: get one mapping (APP), or 404 `mapping_not_found`
            - `PUT /api/v1/apps/NAME` with body `{"target":"http://127.0.0.1:PORT"}`: returns APP \
            with 201 if created, 200 if updated or unchanged
            - `DELETE /api/v1/apps/NAME`: returns 204 whether or not the mapping existed
            - `GET /api/v1/status`: service health, version, and mapping count

            APP looks like this:

            ```json
            {
              "listener": { "pid": 4242, "process": "node" },
              "listening": true,
              "name": "myapp",
              "target": "http://127.0.0.1:43127",
              "url": "\(myapp)"
            }
            ```

            `listening` says whether a process has the target's port open right now. Subpanel \
            reads it from the OS socket table and never connects to your app to check. \
            `listener` names that process. `false` means nothing is bound there yet. The \
            mapping still exists and still routes.

            Errors look like `{"error": {"code": "invalid_name", "message": "..."}}`. The `message` \
            explains the fix. The codes are:

            - 400: `invalid_name`, `invalid_target`, `non_loopback_target`, `malformed_json`
            - 409: `reserved_name`
            - 404: `mapping_not_found`, `not_found`
            - 502, from `NAME.localhost`: `backend_unavailable`

            **Names:** use `a-z`, `0-9`, and `-`, starting and ending with a letter or digit, at \
            most 63 characters. Send the bare label (`myapp`), not `myapp.localhost`. Uppercase is \
            rejected rather than silently lowercased. `subpanel` is reserved.

            **Targets:** `http://127.0.0.1:PORT`, `http://[::1]:PORT`, or `http://localhost:PORT`. \
            The port is required, and it can't be 80.

            ## What your app sees

            - The original `Host` header (`myapp.localhost`) is preserved. Subpanel also sets \
            `X-Forwarded-Host`, `X-Forwarded-Proto: http`, `X-Forwarded-For`, and `Forwarded`.
            - WebSockets (including dev-server HMR), server-sent events, streaming, and large \
            uploads and downloads all pass through unbuffered.
            - Servers that check the Host header have to accept `myapp.localhost`. Vite accepts \
            `*.localhost` by default. For others, allow `.localhost` (for example webpack \
            `allowedHosts` or Django `ALLOWED_HOSTS`).

            ## Troubleshooting

            - `404` from `\(myapp)`: the name isn't registered. PUT it.
            - `502` from `\(myapp)`: the name is registered, but nothing answered at the target. \
            Start the app, or PUT its new port.
            - Check a mapping: `curl -sS \(api)/apps/myapp`
            - Check Subpanel itself: `curl -sS \(api)/status`

            This document is served at \(base)/instructions (Markdown, also at \
            `/instructions.md` and `/llms.txt`), and at \(base)/ for clients that don't ask for HTML.

            """
    }
}
