import SwiftUI

/// Shows the model's last failed action as an alert. Attached to every
/// window, so an error surfaces wherever the user is looking — including one
/// that happened while this window was closed.
struct ActionErrorAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert("Something Went Wrong", isPresented: $model.isShowingActionError) {
                Button("OK") {}
            } message: {
                Text(model.actionError ?? "")
            }
    }
}

extension View {
    func actionErrorAlert() -> some View {
        modifier(ActionErrorAlert())
    }
}
