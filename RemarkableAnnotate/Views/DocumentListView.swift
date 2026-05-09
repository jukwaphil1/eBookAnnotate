import SwiftUI

struct DocumentListView: View {
    @Bindable var vm: AppViewModel
    let documents: [RemarkableDocument]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(documents.count) annotated document\(documents.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Disconnect", action: vm.disconnect)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if let result = vm.lastResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.green.opacity(0.08))
            }

            if case .error(let msg) = vm.state {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(msg).font(.callout).foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.red.opacity(0.06))
            }

            if documents.isEmpty {
                Spacer()
                Text("No highlighted PDFs found on device.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(documents) { doc in
                    DocumentRow(doc: doc, isExtracting: vm.extracting == doc.uuid) {
                        vm.extract(document: doc)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

private struct DocumentRow: View {
    let doc: RemarkableDocument
    let isExtracting: Bool
    let onExtract: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.body)
                Text("\(doc.highlightCount) highlight\(doc.highlightCount == 1 ? "" : "s") · \(doc.pageCount) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isExtracting {
                ProgressView().scaleEffect(0.7)
            } else {
                Button("Extract", action: onExtract)
                    .buttonStyle(.bordered)
                    .disabled(false)
            }
        }
        .padding(.vertical, 4)
    }
}
