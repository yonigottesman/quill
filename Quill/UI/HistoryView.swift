import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                Spacer()
                Text("No fixes yet").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(store.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.before)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .textSelection(.enabled)
                        Text(entry.after)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Clear") { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
            .padding(8)
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}
