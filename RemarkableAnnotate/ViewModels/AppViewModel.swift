import Foundation
import AppKit

@MainActor @Observable
final class AppViewModel {
    var host = "10.11.99.1"
    var password = ""

    enum State {
        case idle
        case checkingDeps
        case installingDeps
        case connecting
        case connected([RemarkableDocument])
        case error(String)
    }

    var state: State = .idle
    var extracting: String? = nil   // uuid currently being extracted
    var lastResult: String? = nil   // success message after extraction

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
        password = ""
    }

    func extract(document: RemarkableDocument) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let h = host, pw = password, uuid = document.uuid
        extracting = uuid
        lastResult = nil

        Task {
            let result = await service.extractDocument(host: h, password: pw, uuid: uuid, to: url)
            extracting = nil
            switch result {
            case .success(let count):
                lastResult = "Saved \(count) highlight\(count == 1 ? "" : "s") to \(url.lastPathComponent)"
            case .failure(let err):
                state = .error(err.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func doConnect() async {
        state = .connecting
        let result = await service.listDocuments(host: host, password: password)
        switch result {
        case .success(let docs):
            state = .connected(docs)
        case .failure(let err):
            state = .error(err.localizedDescription)
        }
    }
}
