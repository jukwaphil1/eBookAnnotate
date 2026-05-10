import Foundation
import AppKit
import UniformTypeIdentifiers

enum DeviceSource { case remarkable, kindle }

@MainActor @Observable
final class AppViewModel {
    var host: String {
        get { UserDefaults.standard.string(forKey: "remarkableHost") ?? "10.11.99.1" }
        set { UserDefaults.standard.set(newValue, forKey: "remarkableHost") }
    }

    enum DeviceStatus { case unknown, detecting, detected, notFound }

    enum State {
        case idle
        case checkingDeps
        case installingDeps
        case connecting
        case connectedRemarkable([DeviceNode])
        case connectedKindle([KindleBook])
        case error(String)
    }

    var state: State = .idle
    var extracting: String? = nil
    var lastResult: String? = nil
    var remarkableStatus: DeviceStatus = .unknown
    var kindleStatus: DeviceStatus = .unknown
    var connectingSource: DeviceSource? = nil

    private var kindleClippingsPath: String? = nil
    private let service = ExtractionService.shared

    var extractedUUIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: "extractedUUIDs") ?? []
            return Set(arr)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: "extractedUUIDs") }
    }

    var isWorking: Bool {
        switch state {
        case .checkingDeps, .installingDeps, .connecting: return true
        default: return extracting != nil
        }
    }

    func detectDevices() {
        remarkableStatus = .detecting
        kindleStatus = .detecting
        let h = host
        Task {
            async let rmFound = service.checkRemarkable(host: h)
            let clippings = service.findKindleClippings()
            remarkableStatus = await rmFound ? .detected : .notFound
            kindleClippingsPath = clippings
            kindleStatus = clippings != nil ? .detected : .notFound
        }
    }

    func connect(source: DeviceSource) {
        connectingSource = source
        state = .checkingDeps
        lastResult = nil
        Task {
            let hasDeps = await service.checkDependencies()
            if hasDeps {
                await doConnect(source: source)
            } else {
                state = .installingDeps
                let (ok, errMsg) = await service.installDependencies()
                if ok {
                    await doConnect(source: source)
                } else {
                    connectingSource = nil
                    state = .error("Could not install Python packages:\n\(errMsg)")
                }
            }
        }
    }

    func disconnect() {
        state = .idle
        connectingSource = nil
        detectDevices()
    }

    func extract(uuid: String, title: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".docx"
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let h = host
        extracting = uuid
        lastResult = nil

        Task {
            let result = await service.extractDocument(host: h, uuid: uuid, title: title, to: url)
            extracting = nil
            switch result {
            case .success(let count):
                if count > 0 {
                    var uuids = extractedUUIDs
                    uuids.insert(uuid)
                    extractedUUIDs = uuids
                    lastResult = "Saved \(count) highlight\(count == 1 ? "" : "s") to \(url.lastPathComponent)"
                } else {
                    lastResult = "No highlights found in \"\(title)\"."
                }
            case .failure(let err):
                state = .error(err.localizedDescription)
            }
        }
    }

    func extractKindle(book: KindleBook) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = book.title.replacingOccurrences(of: "/", with: "-") + ".docx"
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        extracting = book.id
        lastResult = nil

        Task {
            let result = await service.extractKindleBook(
                clippingsPath: book.clippingsPath,
                bookTitle: book.title,
                to: url
            )
            extracting = nil
            switch result {
            case .success(let count):
                if count > 0 {
                    var uuids = extractedUUIDs
                    uuids.insert(book.id)
                    extractedUUIDs = uuids
                    lastResult = "Saved \(count) highlight\(count == 1 ? "" : "s") to \(url.lastPathComponent)"
                } else {
                    lastResult = "No highlights found in \"\(book.title)\"."
                }
            case .failure(let err):
                state = .error(err.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func doConnect(source: DeviceSource) async {
        state = .connecting
        switch source {
        case .remarkable:
            let result = await service.listTree(host: host)
            switch result {
            case .success(let nodes):
                connectingSource = nil
                state = .connectedRemarkable(nodes)
            case .failure(let err):
                connectingSource = nil
                state = .error(err.localizedDescription)
            }
        case .kindle:
            let path = service.findKindleClippings()
            guard let path else {
                connectingSource = nil
                state = .error("Kindle clippings file not found.\nMake sure your Kindle is connected via USB.")
                return
            }
            let result = await service.listKindleBooks(clippingsPath: path)
            switch result {
            case .success(let books):
                kindleClippingsPath = path
                connectingSource = nil
                state = .connectedKindle(books)
            case .failure(let err):
                connectingSource = nil
                state = .error(err.localizedDescription)
            }
        }
    }
}
