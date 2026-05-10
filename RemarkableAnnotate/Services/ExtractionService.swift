import Foundation

final class ExtractionService {
    static let shared = ExtractionService()

    private var _pythonPath: String?
    private var pythonPath: String {
        if let cached = _pythonPath { return cached }
        let path = resolvePython()
        _pythonPath = path
        return path
    }

    private func resolvePython() -> String {
        var candidates: [String] = []

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        whichProcess.arguments = ["-l", "-c", "which python3"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = Pipe()
        if let _ = try? whichProcess.run() {
            whichProcess.waitUntilExit()
            let out = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !out.isEmpty { candidates.append(out) }
        }

        candidates += [
            "/opt/homebrew/Caskroom/miniforge/base/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: candidate)
            p.arguments = ["-c", "import requests, fitz, rmscene"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            if let _ = try? p.run() {
                p.waitUntilExit()
                if p.terminationStatus == 0 { return candidate }
            }
        }

        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/python3"
    }

    private var scriptPath: String {
        Bundle.main.path(forResource: "extract", ofType: "py") ?? "(script not found in bundle)"
    }

    // MARK: - Public

    func diagnostics(host: String) async -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var lines: [String] = ["=== RemarkableAnnotate \(version) (build \(build)) ==="]

        let whichResult = shellOutput("/bin/zsh", ["-l", "-c", "which python3"])
        lines.append("login-shell which python3: \(whichResult.trimmingCharacters(in: .whitespacesAndNewlines))")

        for c in ["/opt/homebrew/Caskroom/miniforge/base/bin/python3",
                  "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            lines.append("\(c): \(FileManager.default.fileExists(atPath: c) ? "exists" : "not found")")
        }

        lines.append("resolved python: \(pythonPath)")

        let ver = await run(python: ["--version"])
        lines.append("python version: \((ver.stdout + ver.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")

        let imp = await run(python: ["-c", "import requests, rmscene; print('imports ok')"])
        lines.append("import check (exit \(imp.code)): \((imp.stdout + imp.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")

        lines.append("script path: \(scriptPath)")
        lines.append("script exists: \(FileManager.default.fileExists(atPath: scriptPath))")

        lines.append("")
        lines.append("--- list command (host: \(host)) ---")
        let list = await run(script: ["list", host])
        lines.append("exit code: \(list.code)")
        if !list.stdout.isEmpty { lines.append("stdout:\n\(list.stdout)") }
        if !list.stderr.isEmpty { lines.append("stderr:\n\(list.stderr)") }

        return lines.joined(separator: "\n")
    }

    func checkRemarkable(host: String) async -> Bool {
        guard let url = URL(string: "http://\(host)/documents/") else { return false }
        let request = URLRequest(url: url, timeoutInterval: 3)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func findKindleClippings() -> String? {
        let fm = FileManager.default
        guard let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return nil }
        for vol in vols {
            let path = "/Volumes/\(vol)/documents/My Clippings.txt"
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func checkDependencies() async -> Bool {
        let r = await run(python: ["-c", "import requests, rmscene, docx"])
        return r.code == 0
    }

    func installDependencies() async -> (success: Bool, error: String) {
        let r = await run(python: ["-m", "pip", "install", "--quiet",
                                   "requests", "rmscene", "python-docx"])
        return (r.code == 0, r.stderr.isEmpty ? r.stdout : r.stderr)
    }

    func listKindleBooks(clippingsPath: String) async -> Result<[KindleBook], Error> {
        let r = await run(script: ["kindle-list", clippingsPath])
        guard r.code == 0 else { return .failure(scriptError(from: r)) }
        struct BookJSON: Decodable { let title: String; let author: String; let highlight_count: Int }
        struct R: Decodable { let books: [BookJSON] }
        guard let data = r.stdout.data(using: .utf8) else { return .failure(AppError("Empty response")) }
        do {
            let decoded = try JSONDecoder().decode(R.self, from: data)
            let books = decoded.books.map { b in
                KindleBook(id: b.title, title: b.title, author: b.author,
                           highlightCount: b.highlight_count, clippingsPath: clippingsPath)
            }
            return .success(books)
        } catch {
            return .failure(error)
        }
    }

    func extractKindleBook(clippingsPath: String, bookTitle: String, to url: URL) async -> Result<Int, Error> {
        let r = await run(script: ["kindle-extract", clippingsPath, bookTitle, url.path])
        guard r.code == 0 else { return .failure(scriptError(from: r)) }
        if let data = r.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let count = json["highlight_count"] as? Int {
            return .success(count)
        }
        return .success(0)
    }

    func listTree(host: String) async -> Result<[DeviceNode], Error> {
        let r = await run(script: ["list", host])
        guard r.code == 0 else { return .failure(scriptError(from: r)) }
        struct R: Decodable { let tree: [DeviceNode] }
        guard let data = r.stdout.data(using: .utf8) else { return .failure(AppError("Empty response")) }
        do {
            return .success(try JSONDecoder().decode(R.self, from: data).tree)
        } catch {
            return .failure(error)
        }
    }

    func extractDocument(host: String, uuid: String, title: String, to url: URL) async -> Result<Int, Error> {
        let r = await run(script: ["extract", host, uuid, url.path, title])
        guard r.code == 0 else { return .failure(scriptError(from: r)) }
        if !r.stderr.isEmpty {
            _lastExtractionDebug = r.stderr
        }
        if let data = r.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let count = json["highlight_count"] as? Int {
            return .success(count)
        }
        return .success(0)
    }

    private(set) var _lastExtractionDebug: String = ""

    private func scriptError(from r: RunResult) -> ScriptError {
        let raw = r.stdout.isEmpty ? r.stderr : r.stdout
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            return ScriptError(message: msg, raw: raw)
        }
        return ScriptError(message: raw.isEmpty ? "Unknown error (exit \(r.code))" : raw, raw: raw)
    }

    // MARK: - Private

    private struct RunResult { let code: Int32; let stdout: String; let stderr: String }

    private func shellOutput(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func run(script args: [String]) async -> RunResult {
        let script = scriptPath
        return await run(python: [script] + args)
    }

    private func run(python args: [String]) async -> RunResult {
        let exe = pythonPath
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run(); p.waitUntilExit() } catch {
                    cont.resume(returning: RunResult(code: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                cont.resume(returning: RunResult(
                    code: p.terminationStatus,
                    stdout: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    stderr: String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                ))
            }
        }
    }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ msg: String) { errorDescription = msg.isEmpty ? "Unknown error" : msg }
}

struct ScriptError: LocalizedError {
    let errorDescription: String?
    let raw: String
    init(message: String, raw: String) {
        errorDescription = message.isEmpty ? "Unknown error" : message
        self.raw = raw
    }
}
