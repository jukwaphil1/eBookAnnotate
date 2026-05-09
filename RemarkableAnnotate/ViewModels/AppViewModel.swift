import Foundation
import AppKit

@MainActor @Observable
final class AppViewModel {
    var host = "10.11.99.1"

    enum State {
        case idle
        case checkingDeps
        case installingDeps
        case connecting
        case connected([DeviceNode])
        case error(String)
    }

    var state: State = .idle
    var extracting: String? = nil
    var lastResult: String? = nil
    var diagnosticOutput: String? = nil
    var showDiagnostics = false

    private let service = ExtractionService.shared

    var isWorking: Bool {
        switch state {
        case .checkingDeps, .installingDeps, .connecting: return true
        default: return extracting != nil
        }
    }

    func connect() {
        state = .checkingDeps
        lastResult = nil
        Task {
            let hasDeps = await service.checkDependencies()
            if hasDeps {
                await doConnect()
            } else {
                state = .installingDeps
                let (ok, errMsg) = await service.installDependencies()
                if ok {
                    await doConnect()
                } else {
                    state = .error("Could not install Python packages:\n\(errMsg)")
                }
            }
        }
    }

    func disconnect() {
        state = .idle
    }

    func runDiagnostics() {
        diagnosticOutput = "Running…"
        showDiagnostics = true
        Task {
            diagnosticOutput = await service.diagnostics()
        }
    }

    func extract(uuid: String, title: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let h = host
        extracting = uuid
        lastResult = nil

        Task {
            let result = await service.extractDocument(host: h, uuid: uuid, to: url)
            extracting = nil
            switch result {
            case .success(let count):
                if count == 0 {
                    lastResult = "No highlights found in \"\(title)\"."
                } else {
                    lastResult = "Saved \(count) highlight\(count == 1 ? "" : "s") to \(url.lastPathComponent)"
                }
            case .failure(let err):
                state = .error(err.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func doConnect() async {
        state = .connecting
        let result = await service.listTree(host: host)
        switch result {
        case .success(let nodes):
            state = .connected(nodes)
        case .failure(let err):
            state = .error(err.localizedDescription)
        }
    }
}
