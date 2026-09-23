# Problems — things that bit us

One entry per hard-won pattern lesson (`SWIFTUI-RULES.md` §10.2). Keep these
separate from commit messages, where they get lost. The big SwiftUI catalogue
lives in `SWIFTUI-RULES.md`; this file is for issues specific to *this* app.

The template starts with none of its own. The note below is a standing
gotcha for anyone forking it.

---

## Renaming has to keep four names in agreement

The SwiftPM target name, the `.app` name in `build.sh` (`APP_NAME`), the
`CFBundleExecutable` in `Info.plist`, and the entitlements path
(`<Name>/<Name>.entitlements`) must all be the same string, or the build
assembles an `.app` whose executable name doesn't match the bundle and macOS
refuses to launch it. That coupling is exactly why `scripts/rename.sh` exists —
prefer it over a hand find-replace, which is easy to do incompletely. See
[plans/renaming.md](plans/renaming.md).
