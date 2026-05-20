import SwiftUI

struct ConnectionView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                Text("eBook Annotate")
                    .font(.title2.bold())
                Text("Connect a device via USB to extract your highlights.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if case .error(let msg) = vm.state {
                VStack(spacing: 12) {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)

                    if msg.localizedCaseInsensitiveContains("remarkable") {
                        RemarkableHelpBox()
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                DeviceCard(
                    icon: "pencil.and.list.clipboard",
                    name: "reMarkable",
                    status: vm.remarkableStatus,
                    isConnecting: vm.connectingSource == .remarkable && vm.isWorking,
                    isDisabled: vm.isWorking
                ) {
                    vm.connect(source: .remarkable)
                }

                DeviceCard(
                    icon: "book",
                    name: "Kindle",
                    status: vm.kindleStatus,
                    isConnecting: vm.connectingSource == .kindle && vm.isWorking,
                    isDisabled: vm.isWorking
                ) {
                    vm.connect(source: .kindle)
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(32)
        .onAppear { vm.detectDevices() }
    }
}

private struct RemarkableHelpBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enable the USB web interface on your reMarkable")
                .font(.callout.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Label("Wake the tablet (it must be awake to connect)", systemImage: "1.circle")
                Label("Open Menu → Settings → Storage", systemImage: "2.circle")
                Label("Toggle \"USB web interface\" on", systemImage: "3.circle")
                Label("Plug in with a data-capable USB-C cable", systemImage: "4.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DeviceCard: View {
    let icon: String
    let name: String
    let status: AppViewModel.DeviceStatus
    let isConnecting: Bool
    let isDisabled: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(iconForeground)
            }

            VStack(spacing: 4) {
                Text(name).font(.headline)
                HStack(spacing: 5) {
                    if status == .detecting {
                        ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onConnect) {
                if isConnecting {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text(connectingLabel)
                    }
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
            .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusLabel: String {
        switch status {
        case .unknown:    return "Connect via USB"
        case .detecting:  return "Detecting…"
        case .detected:   return "Ready"
        case .notFound:   return "Not connected"
        }
    }

    private var connectingLabel: String { "Connecting…" }

    private var dotColor: Color {
        switch status {
        case .detected:  return .green
        case .notFound:  return Color.secondary.opacity(0.4)
        default:         return .clear
        }
    }

    private var iconForeground: Color {
        status == .detected ? .accentColor : .secondary
    }

    private var iconBackground: Color {
        status == .detected
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(0.06)
    }
}
