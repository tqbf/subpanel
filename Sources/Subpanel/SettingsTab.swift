/// The Settings window's tabs. Stored, so Settings reopens where you left it
/// (and `-settingsTab service` on the command line opens a specific one).
enum SettingsTab: String {
    case general
    case service
    case diagnostics
}
