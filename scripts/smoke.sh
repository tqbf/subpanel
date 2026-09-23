#!/usr/bin/env bash
#
# smoke.sh — end-to-end checks against the Subpanel service on port 80.
#
# Exercises the real thing — launchd-activated sockets, the installed agent,
# the on-disk registry — the way an agent would: curl + a throwaway backend.
# Leaves no mappings behind. Needs only curl and python3.
#
#   ./scripts/smoke.sh            # against http://subpanel.localhost (port 80)
#   BASE=http://subpanel.localhost:8080 ./scripts/smoke.sh   # against `make service-dev`
set -uo pipefail

BASE="${BASE:-http://subpanel.localhost}"
PORT_SUFFIX="$(printf '%s' "$BASE" | sed -n 's|^http://[^:/]*\(:[0-9]*\).*|\1|p')"
NAME="smoke-$$"
APP="http://$NAME.localhost$PORT_SUFFIX"
failures=0
pids=()

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
serve() {  # serve <port> <marker> — a backend that answers with its marker
	local dir; dir="$(mktemp -d)"
	printf '%s' "$2" > "$dir/index.html"
	python3 -m http.server "$1" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
	pids+=($!)
	disown  # no "Terminated" noise when we kill it
	for _ in $(seq 50); do curl -fs "http://127.0.0.1:$1/" >/dev/null 2>&1 && return; sleep 0.1; done
}
put() { curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/api/v1/apps/$NAME" \
	-H 'Content-Type: application/json' -d "{\"target\":\"http://127.0.0.1:$1\"}"; }
cleanup() {
	curl -s -o /dev/null -X DELETE "$BASE/api/v1/apps/$NAME"
	for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null; done
}
trap cleanup EXIT

echo "→ Subpanel smoke test against $BASE"

status="$(curl -fsS -m 3 "$BASE/api/v1/status" 2>/dev/null)"
if [ -z "$status" ]; then
	fail "service answers at $BASE (is it installed? try: make install)"
	exit 1
fi
summary="$(printf '%s' "$status" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("v%s, pid %s, %s" % (d["version"], d["pid"], ", ".join(d["listeners"])))')"
pass "service answers ($summary)"

check "instructions are Markdown" \
	'[ "$(curl -s -o /dev/null -w "%{content_type}" "$BASE/instructions")" = "text/markdown; charset=utf-8" ]'
check "bare / serves the instructions to curl" \
	'curl -s "$BASE/" | head -1 | grep -q "^# Subpanel"'
check "discovery document" \
	'curl -s "$BASE/.well-known/subpanel" | grep -q "\"websocket\" : true"'

first="$(free_port)"; serve "$first" "first-backend"
second="$(free_port)"; serve "$second" "second-backend"

check "PUT creates the mapping (201)" '[ "$(put "$first")" = 201 ]'
check "PUT again is idempotent (200)" '[ "$(put "$first")" = 200 ]'
check "$APP routes to the backend" 'curl -fs "$APP/" | grep -q first-backend'
check "…over IPv4 (127.0.0.1)" 'curl -4 -fs "$APP/" | grep -q first-backend'
check "…and over IPv6 ([::1])" 'curl -6 -fs "$APP/" | grep -q first-backend'
check "PUT a new port takes effect immediately" '[ "$(put "$second")" = 200 ] && curl -fs "$APP/" | grep -q second-backend'
check "the mapping is persisted to disk" \
	'grep -q "\"$NAME\"" "$(printf "%s" "$status" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"registryPath\"])")"'

kill "${pids[1]}" 2>/dev/null; sleep 0.3
check "backend down → 502 naming the target" \
	'[ "$(curl -s -o /dev/null -w "%{http_code}" "$APP/")" = 502 ] && curl -s "$APP/" | grep -q "Target: 127.0.0.1:$second"'

check "DELETE → 204" '[ "$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/v1/apps/$NAME")" = 204 ]'
check "deleted name → 404" '[ "$(curl -s -o /dev/null -w "%{http_code}" "$APP/")" = 404 ]'
check "reserved name rejected (409)" \
	'[ "$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE/api/v1/apps/subpanel" -d "{\"target\":\"http://127.0.0.1:3000\"}")" = 409 ]'
check "non-loopback target rejected (400)" \
	'curl -s -X PUT "$BASE/api/v1/apps/$NAME" -d "{\"target\":\"http://192.168.1.10:3000\"}" | grep -q non_loopback_target'

echo
if [ "$failures" -eq 0 ]; then
	echo "✓ all smoke checks passed"
else
	echo "✗ $failures check(s) failed"
	exit 1
fi
