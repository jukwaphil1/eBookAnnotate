import SwiftUI

struct DiagnosticsView: View {
    let output: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
    }
}
