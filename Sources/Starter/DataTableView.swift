import SwiftUI

/// The table destination: a native, sortable `Table` over the demo rows. The
/// footer shows a live count — the kind of quiet metadata a real macOS app
/// keeps at the bottom of a list.
struct DataTableView: View {
    let items: [SampleItem]

    @State private var sortOrder = [KeyPathComparator(\SampleItem.name)]
    @State private var selection: SampleItem.ID?

    private var sortedItems: [SampleItem] {
        items.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedItems, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                Text(item.name).font(Theme.Fonts.tableCell)
            }
            TableColumn("Category", value: \.category) { item in
                Text(item.category).font(Theme.Fonts.tableCell)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Status", value: \.status) { item in
                StatusBadge(status: item.status)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Value", value: \.value) { item in
                Text(item.value, format: .number.precision(.fractionLength(2)))
                    .font(Theme.Fonts.tableNumber)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 96)

            TableColumn("Updated", value: \.updated) { item in
                Text(item.updated, format: .relative(presentation: .named))
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
        }
        .navigationTitle(SidebarSection.table.title)
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private var footer: some View {
        HStack {
            Text("\(items.count) items")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
