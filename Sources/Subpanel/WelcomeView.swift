import SwiftUI

/// First run, in one screen: what Subpanel does, that it's running, and the
/// one URL to give coding agents. Installing the service happens here.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        VStack(spacing: Theme.stackSpacing) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: Theme.welcomeIconSize, height: Theme.welcomeIconSize)
                .accessibilityHidden(true)

            VStack(spacing: Theme.tightSpacing) {
                Text("Welcome to Subpanel")
                    .font(Theme.Fonts.welcomeTitle)
                Text(verbatim: "Stable URLs like myapp.localhost for your local web apps.")
                    .font(Theme.Fonts.lead)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WelcomeStatus()

            VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                Text("Agent instructions")
                    .font(Theme.Fonts.label)
                CodeBox(value: model.instructionsURL.absoluteString)
                Text("Give this URL to your coding agents. It tells them how to register the apps they build.")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Copy Instructions URL", action: copyURL)
                Button("Open Instructions", action: openInstructions)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.welcomePadding)
        .frame(width: Theme.welcomeWidth)
        .actionErrorAlert()
        .task { await model.installServiceIfNeeded() }
        // However the window closes, don't show it again (but snapshot runs
        // don't count — they share the installed app's defaults).
        .onDisappear { hasSeenWelcome = hasSeenWelcome || DevSnapshot.directory == nil }
    }

    private func copyURL() {
        Desktop.copy(model.instructionsURL.absoluteString)
    }

    private func openInstructions() {
        Desktop.open(model.instructionsURL)
    }

    private func done() {
        dismissWindow(id: WindowID.welcome)
    }
}
