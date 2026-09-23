# Renaming the template

You forked by `cp -R`. `scripts/rename.sh` turns "Subpanel" into your app's name
in one pass.

```sh
./scripts/rename.sh NewName                 # bundle id → org.sockpuppet.newname
./scripts/rename.sh NewName com.you.newname # …or supply your own bundle id
```

`NewName` must be a valid Swift identifier (letters/digits/underscore, not
starting with a digit) because it becomes the SwiftPM **target** name. The
script rejects anything else.

## What it rewrites

- **Directories:** `Sources/Subpanel` → `Sources/NewName`,
  `Tests/SubpanelTests` → `Tests/NewNameTests`, `Subpanel/` →  `NewName/`
  (uses `git mv` when the tree is tracked, falls back to `mv`).
- **The entitlements file:** `NewName/Subpanel.entitlements` → `NewName.entitlements`.
- **Every file's contents:** the bundle id (`org.sockpuppet.subpanel` → yours)
  first, then the name `Subpanel` → `NewName`. This covers `Package.swift`,
  `Makefile`, `build.sh`, `Info.plist`, the Swift sources, and the docs.

It skips `.git/`, `build/`, `.build/`, `dist/`, and itself.

## What it deliberately leaves alone

These are yours to set, not mechanical substitutions:

- `VERSION` (already `0.1.0`).
- `Info.plist` → `NSHumanReadableCopyright` and `LSApplicationCategoryType`.
- Prose in `PLAN.md` / `README.md` that describes the *template* rather than
  naming it — rewrite these to describe your app.

## After renaming

```sh
make check   # confirm it still compiles under the new name
make run      # launch NewName
rm scripts/rename.sh   # one-shot; delete it
```

## Doing it by hand

If you'd rather not run the script, the substitutions are exactly: the three
directory moves above, then a project-wide replace of `org.sockpuppet.subpanel`
and then `Subpanel`. Build to confirm — the SwiftPM target name, the `.app`
name in `build.sh`, the `CFBundleExecutable`, and the entitlements path all
have to agree, which is the whole reason the script exists.
