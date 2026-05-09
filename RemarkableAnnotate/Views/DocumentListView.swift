import SwiftUI

struct DocumentListView: View {
    @Bindable var vm: AppViewModel
    let documents: [RemarkableDocument]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(documents.count) document\(documents.count == 1 ? "" : "s")")
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
                Text("No documents found on device.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(documents) { doc in
                    HStack {
                        Text(doc.title)
                            .font(.body)
                        Spacer()
                        if vm.extracting == doc.uuid {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Extract") { vm.extract(document: doc) }
                                .buttonStyle(.bordered)
                                .disabled(vm.extracting != nil)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
