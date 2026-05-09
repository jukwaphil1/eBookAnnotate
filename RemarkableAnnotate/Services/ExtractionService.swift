import Foundation

final class ExtractionService {
    static let shared = ExtractionService()

    // Resolved once and cached — finding the right Python involves process spawning.
    private var _pythonPath: String?
    private var pythonPath: String {
        if let cached = _pythonPath { return cached }
        let path = resolvePython()
        _pythonPath = path
        return path
    }

    private func resolvePython() -> String {
        // Collect candidates: login-shell `which python3` plus well-known locations.
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

        // Return the first Python that can actually import our dependencies.
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

        // Nothing has deps yet — return first existing Python so install can run.
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/python3"
    }

    private var scriptPath: String {
        Bundle.main.path(forResource: "extract", ofType: "py") ?? ""
    }

    func checkDependencies() async -> Bool {
        let r = await run(python: ["-c", "import requests, fitz, rmscene"])
        return r.code == 0
    }

    func installDependencies() async -> (success: Bool, error: String) {
        let r = await run(python: ["-m", "pip", "install", "--quiet",
                                   "requests", "pymupdf", "rmscene"])
        return (r.code == 0, r.stderr)
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
