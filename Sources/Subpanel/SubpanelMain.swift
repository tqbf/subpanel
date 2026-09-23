import Foundation

/// Entry point. `Subpanel --install-service` (and friends) manage the
/// LaunchAgent headlessly — for `make install`, scripts, and agents — and
/// exit without showing any UI. Otherwise this is the menu-bar app.
@main
enum SubpanelMain {
    static func main() {
        if let command = ServiceCommand(arguments: CommandLine.arguments) {
            exit(command.run())
        }
        SubpanelApp.main()
    }
}
