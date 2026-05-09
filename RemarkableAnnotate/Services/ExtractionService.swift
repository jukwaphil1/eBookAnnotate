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

    func diagnostics() async -> String {
        var lines: [String] = ["=== RemarkableAnnotate diagnostics ==="]

        // Python candidates
        let whichResult = shellOutput("/bin/zsh", ["-l", "-c", "which python3"])
        lines.append("login-shell which python3: \(whichResult.trimmingCharacters(in: .whitespacesAndNewlines))")

        let allCandidates = [
            "/opt/homebrew/Caskroom/miniforge/base/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for c in allCandidates {
            let exists = FileManager.default.fileExists(atPath: c)
            lines.append("\(c): \(exists ? "exists" : "not found")")
        }

        lines.append("resolved python: \(pythonPath)")

        // Version
        let verResult = await run(python: ["--version"])
        lines.append("python version: \(verResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) \(verResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Import check
        let importResult = await run(python: ["-c", "import requests, fitz, rmscene; print('imports ok')"])
        lines.append("import check (exit \(importResult.code)):")
        if !importResult.stdout.isEmpty { lines.append("  stdout: \(importResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if !importResult.stderr.isEmpty { lines.append("  stderr: \(importResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }

        // pip install dry-run
        let pipResult = await run(python: ["-m", "pip", "install", "--quiet", "requests", "pymupdf", "rmscene"])
        lines.append("pip install (exit \(pipResult.code)):")
        if !pipResult.stdout.isEmpty { lines.append("  stdout: \(pipResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if !pipResult.stderr.isEmpty { lines.append("  stderr: \(pipResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }

        // Script path
        lines.append("script path: \(scriptPath)")
        lines.append("script exists: \(FileManager.default.fileExists(atPath: scriptPath))")

        return lines.joined(separator: "\n")
    }

    func checkDependencies() async -> Bool {
        let r = await run(python: ["-c", "import requests, fitz, rmscene"])
        return r.code == 0
    }

    func installDependencies() async -> (success: Bool, error: String) {
        let r = await run(python: ["-m", "pip", "install", "--quiet",
                                   "requests", "pymupdf", "rmscene"])
        return (r.code == 0, r.stderr.isEmpty ? r.stdout : r.stderr)
    }

    func listDocuments(host: String) async -> Result<[RemarkableDocument], Error> {
        let r = await run(script: ["list", host])
        guard r.code == 0 else {
            return .failure(AppError(r.stderr.isEmpty ? r.stdout : r.stderr))
        }
        return decode(r.stdout)
    }

    func extractDocument(host: String, uuid: String, to url: URL) async -> Result<Int, Error> {
        let r = await run(script: ["extract", host, uuid, url.path])
        guard r.code == 0 else {
            return .failure(AppError(r.stderr.isEmpty ? r.stdout : r.stderr))
        }
        if let data = r.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let count = json["highlight_count"] as? Int {
            return .success(count)
        }
        return .success(0)
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

    private func decode(_ json: String) -> Result<[RemarkableDocument], Error> {
        struct R: Decodable { let documents: [RemarkableDocument] }
        guard let data = json.data(using: .utf8) else { return .failure(AppError("Empty response")) }
        do {
            return .success(try JSONDecoder().decode(R.self, from: data).documents)
        } catch {
            return .failure(error)
        }
    }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ msg: String) { errorDescription = msg.isEmpty ? "Unknown error" : msg }
}
