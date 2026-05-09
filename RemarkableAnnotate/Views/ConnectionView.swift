import SwiftUI

struct ConnectionView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                Text("RemarkableAnnotate")
                    .font(.title2.bold())
                Text("Connect your reMarkable via USB, then tap Connect. No password or Developer Mode needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            LabeledContent("Host") {
                TextField("10.11.99.1", text: $vm.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { vm.connect() }
            }

            VStack(spacing: 8) {
                Button(action: { vm.connect() }) {
                    if vm.isWorking {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text(workingLabel)
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.host.isEmpty || vm.isWorking)
                .keyboardShortcut(.return, modifiers: [])

                if case .error(let msg) = vm.state {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        }
        .padding(32)
    }

    private var workingLabel: String {
        switch vm.state {
        case .checkingDeps: return "Checking Python packages…"
        case .installingDeps: return "Installing packages…"
        default: return "Connecting…"
        }
    }
}
