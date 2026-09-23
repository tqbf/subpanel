import SwiftUI

/// The lorem-ipsum reading destination: a single, measure-capped column with
/// a clear type hierarchy (title → lead → headed body sections).
struct ReadingView: View {
    let document: LoremDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.readingSectionSpacing) {
                header

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: Theme.readingHeadingSpacing) {
                        Text(section.heading)
                            .font(Theme.Fonts.sectionHeading)
                        Text(section.body)
                            .font(Theme.Fonts.body)
                            .lineSpacing(Theme.bodyLineSpacing)
                    }
                }
            }
            // Cap the measure, then center the column in whatever width the
            // window gives us.
            .frame(maxWidth: Theme.readingMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.readingHorizontalInset)
            .padding(.top, Theme.readingTopInset)
            .padding(.bottom, Theme.readingBottomInset)
            .textSelection(.enabled)
        }
        .navigationTitle(SidebarSection.reading.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.readingHeadingSpacing) {
            Text(document.title)
                .font(Theme.Fonts.pageTitle)
            Text(document.lead)
                .font(Theme.Fonts.pageLead)
                .foregroundStyle(.secondary)
                .lineSpacing(Theme.bodyLineSpacing)
        }
    }
}
