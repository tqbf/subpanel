import SwiftUI

/// A selectable machine value (a URL) set apart on a quiet background, so it
/// reads as something to copy.
struct CodeBox: View {
    let value: String

    var body: some View {
        Text(value)
            .font(Theme.Fonts.machineValue)
            .textSelection(.enabled)
            .lineLimit(1)
            .padding(Theme.codeBoxPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: Theme.codeBoxCornerRadius))
    }
}
