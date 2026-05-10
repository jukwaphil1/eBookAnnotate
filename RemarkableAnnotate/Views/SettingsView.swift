import SwiftUI

struct SettingsView: View {
    @AppStorage("remarkableHost") private var host = "10.11.99.1"

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Device IP") {
                    TextField("10.11.99.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Text("The default USB address is 10.11.99.1. Only change this if your device uses a different address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}
