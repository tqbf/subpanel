#!/usr/bin/env bash
#
# rename.sh — turn this template into a new app in one pass.
#
# Usage:  ./scripts/rename.sh NewName [org.reverse.dns.bundleid]
#
# Rewrites every "Starter" reference — the SwiftPM target, the .app name, the
# Info.plist, the entitlements, the Makefile/build.sh, the source files and
# their directory — to the name you pass. The new name must be a valid Swift
# identifier (letters/digits/underscore, not starting with a digit) because
# it becomes the executable target name.
#
# If you omit the bundle id, it defaults to org.sockpuppet.<lowercased-name>.
#
# Run this from the repo root, BEFORE your first commit, on a clean tree.
set -euo pipefail

OLD_NAME="Starter"
OLD_BUNDLE="org.sockpuppet.starter"

NEW_NAME="${1:-}"
if [ -z "$NEW_NAME" ]; then
	echo "usage: ./scripts/rename.sh NewName [bundle.id]" >&2
	exit 1
fi
if ! printf '%s' "$NEW_NAME" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
	echo "✗ '$NEW_NAME' is not a valid Swift identifier (target name)." >&2
	echo "  Use letters, digits and underscores; don't start with a digit." >&2
	exit 1
fi

NEW_NAME_LC="$(printf '%s' "$NEW_NAME" | tr '[:upper:]' '[:lower:]')"
NEW_BUNDLE="${2:-org.sockpuppet.$NEW_NAME_LC}"

if [ "$NEW_NAME" = "$OLD_NAME" ]; then
	echo "  nothing to do — already named $OLD_NAME"
	exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ renaming $OLD_NAME → $NEW_NAME (bundle $NEW_BUNDLE)"

# 1. Move the source + entitlements directories first.
[ -d "Sources/$OLD_NAME" ] && git mv "Sources/$OLD_NAME" "Sources/$NEW_NAME" 2>/dev/null \
	|| { [ -d "Sources/$OLD_NAME" ] && mv "Sources/$OLD_NAME" "Sources/$NEW_NAME"; } || true
[ -d "Tests/${OLD_NAME}Tests" ] && git mv "Tests/${OLD_NAME}Tests" "Tests/${NEW_NAME}Tests" 2>/dev/null \
	|| { [ -d "Tests/${OLD_NAME}Tests" ] && mv "Tests/${OLD_NAME}Tests" "Tests/${NEW_NAME}Tests"; } || true
[ -d "$OLD_NAME" ] && git mv "$OLD_NAME" "$NEW_NAME" 2>/dev/null \
	|| { [ -d "$OLD_NAME" ] && mv "$OLD_NAME" "$NEW_NAME"; } || true
[ -f "$NEW_NAME/$OLD_NAME.entitlements" ] && mv "$NEW_NAME/$OLD_NAME.entitlements" "$NEW_NAME/$NEW_NAME.entitlements" || true

# 2. Rewrite file contents. Bundle id first (more specific), then the name.
#    Skip the VCS dir, build outputs, and this script itself.
FILES="$(grep -rIl -e "$OLD_NAME" -e "$OLD_BUNDLE" . \
	--exclude-dir=.git --exclude-dir=.build --exclude-dir=build --exclude-dir=dist \
	--exclude="rename.sh" || true)"

for f in $FILES; do
	# macOS/BSD sed in-place needs the empty backup-suffix argument.
	sed -i '' \
		-e "s/$OLD_BUNDLE/$NEW_BUNDLE/g" \
		-e "s/$OLD_NAME/$NEW_NAME/g" \
		"$f"
done

echo "✓ renamed. Next:"
echo "    make check     # confirm it still compiles"
echo "    make run       # launch $NEW_NAME"
echo "  Then delete scripts/rename.sh if you don't need it again."
