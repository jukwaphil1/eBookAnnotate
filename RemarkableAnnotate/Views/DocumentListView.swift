import SwiftUI

struct DocumentListView: View {
    @Bindable var vm: AppViewModel
    let nodes: [DeviceNode]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("reMarkable")
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

            List(nodes, children: \.optionalChildren) { node in
                NodeRow(node: node, isExtracting: vm.extracting == node.id) {
                    vm.extract(uuid: node.id, title: node.title)
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct NodeRow: View {
    let node: DeviceNode
    let isExtracting: Bool
    let onExtract: () -> Void

    var body: some View {
        HStack {
            Label {
                Text(node.title)
            } icon: {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
            }

            Spacer()

            if case .document = node {
                if isExtracting {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Extract", action: onExtract)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if case .folder = node { return "folder.fill" }
        return "doc.text"
    }

    private var iconColor: Color {
        if case .folder = node { return .yellow }
        return .secondary
    }
}

private extension DeviceNode {
    var optionalChildren: [DeviceNode]? {
        if case .folder(_, _, let children) = self { return children.isEmpty ? nil : children }
        return nil
    }
}
