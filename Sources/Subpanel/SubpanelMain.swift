import Foundation

/// Entry point. `Subpanel --install-service` (and friends) manage the
/// LaunchAgent headlessly — for `make install`, scripts, and agents — and
/// exit without showing any UI. Otherwise this is the Subpanel app.
@main
enum SubpanelMain {
    static func main() {
        if let command = ServiceCommand(arguments: CommandLine.arguments) {
            exit(command.run())
        }
        // An unknown `--flag` is a script talking to a different version of
        // this app. Launching the GUI would hang the script (and a first-run
        // window could re-register the service mid-install: PROBLEMS.md).
        if let flag = CommandLine.arguments.dropFirst().first, flag.hasPrefix("--") {
            FileHandle.standardError.write(Data("Subpanel: unknown option \(flag)\n".utf8))
            exit(64)
        }
        SubpanelApp.main()
    }
}
