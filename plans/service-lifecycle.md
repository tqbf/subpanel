# Service lifecycle: port 80 without root

## The trick: launchd socket activation in a per-user LaunchAgent

Binding 127.0.0.1:80 or [::1]:80 requires root on macOS. (We verified this
on macOS 26: `bind()` returns EACCES. The Mojave relaxation only covers
0.0.0.0, which we won't use.) We don't need root, though:

```xml
<key>Sockets</key>
<dict>
  <key>HTTP4</key> <dict> SockNodeName 127.0.0.1, SockServiceName 80, SockFamily IPv4 </dict>
  <key>HTTP6</key> <dict> SockNodeName ::1,       SockServiceName 80, SockFamily IPv6 </dict>
</dict>
```

in a **per-user LaunchAgent** has *launchd*, which runs as root, create and
bind the sockets. The service, running as you, receives the listening
descriptors from `launch_activate_socket("HTTP4" / "HTTP6")`
(`LaunchdSockets.swift`) and adopts them with NIO's
`ServerBootstrap.withBoundSocket`. There is no privileged helper, no admin
prompt, no root code, and no generic privileged RPC. The only privileged act
is launchd's bind, of exactly two loopback sockets that the plist names.

This gives two properties for free:
- **Crash recovery with no dropped connections.** launchd keeps the sockets
  open while the service is down, so connections queue. `KeepAlive`
  respawns the service, and a new connection also triggers a spawn.
  Verified: after `kill -9`, a request made in the gap was answered in about
  3 ms.
- **User-owned state.** The registry lives in the user's Application Support,
  and nothing in the system is touched.

Plist: `Resources/LaunchAgents/org.sockpuppet.subpanel.service.plist`
(`BundleProgram`: `Contents/MacOS/subpanel-service`, `RunAtLoad`, `KeepAlive`,
`ProcessType Interactive`, `AssociatedBundleIdentifiers`).

## Registration: SMAppService

`SMAppService.agent(plistName: "org.sockpuppet.subpanel.service.plist")`
(`ServiceManager.swift`, `ServiceCommand.swift`):

| Action | How |
|---|---|
| install | `register()`. launchd loads the job, which starts now and at every login. It appears in System Settings → General → Login Items. |
| repair / reinstall | `unregister()` then `register()`, which re-points the job at *this* copy of the app |
| restart | `launchctl kickstart -k gui/<uid>/org.sockpuppet.subpanel.service` |
| status | `SMAppService.status`: `.enabled`, `.requiresApproval` (the user turned it off in Login Items), `.notRegistered`, or `.notFound` (the bundle lacks the plist) |

The same actions are available headlessly, along with the menu-bar app's
login item (`SMAppService.loginItem(identifier: "org.sockpuppet.subpanel.menu")`
for the nested `Contents/Library/LoginItems/SubpanelMenu.app`):

```sh
/Applications/Subpanel.app/Contents/MacOS/Subpanel --install-service
/Applications/Subpanel.app/Contents/MacOS/Subpanel --uninstall-service
/Applications/Subpanel.app/Contents/MacOS/Subpanel --install-menu     # registers + launches it
/Applications/Subpanel.app/Contents/MacOS/Subpanel --uninstall-menu
/Applications/Subpanel.app/Contents/MacOS/Subpanel --service-status   # both items
```

Any other `--flag` exits with status 64 instead of launching the GUI.

`make install` first retires the existing registrations, **using the new
build's binary** (it can unregister items made by either copy) and quits
running copies of both apps. Then it copies the app to /Applications and
runs `--install-service` and `--install-menu`. Never drive an *older*
installed binary with flags it may not know. That once launched the old GUI
mid-install, and its first-run window re-registered the service from a bundle
that was about to be deleted, which left launchd with an unresolvable job
(PROBLEMS.md).

This **works with an ad-hoc-signed build.** A Developer ID is needed only for
distribution.

### One copy at a time (important)

Registering the agent from `build/Subpanel.app` and then from
`/Applications/Subpanel.app` (same bundle ID) confused Background Task
Management. BTM had resolved the agent through the `build/` copy, whose code
hash changes on every rebuild. launchd was left with a job it couldn't
resolve ("Could not find and/or execute program … No such process") and
retried every 10 s while connections to port 80 hung. The fix is to
unregister from **both** copies and then register from one. `make install`
now does this. See PROBLEMS.md.

## The apps' role

Both apps observe the service; neither hosts it. On first run Subpanel.app's
Welcome window registers the agent and the menu-bar item if they've never
been registered. Settings → General toggles the menu-bar item. Settings →
Service shows status, the login-item state, and listeners, and offers Restart
and Reinstall. If the service is down, the Apps window offers the one fix
that matches the actual state (Start, Restart, or Open Login Items), and the
menu-bar icon turns into a warning triangle.

## Development mode (no launchd, no port 80)

```sh
make service-dev      # subpanel-service --port 8080 --registry /tmp/subpanel-dev-registry.json --verbose
SUBPANEL_BASE_URL=http://subpanel.localhost:8080 open build/Subpanel.app
BASE=http://subpanel.localhost:8080 ./scripts/smoke.sh
```

With `--port N`, the service binds 127.0.0.1:N and [::1]:N itself, and every
generated URL includes `:N`. Without `--port` and outside launchd, it exits
with EX_CONFIG (78) and a message telling you to pass `--port`.

## Logging

Unified logging with subsystem `org.sockpuppet.subpanel` and categories
`service`, `proxy`, `registry`, and `api`:

```sh
log stream --predicate 'subsystem == "org.sockpuppet.subpanel"' --info
```

Logged: startup and shutdown, registry load and save failures, mapping
changes, backend failures (info level), listener failures, and rejected API
input. Bodies are never logged. `--verbose` adds a debug-level line per
request.
