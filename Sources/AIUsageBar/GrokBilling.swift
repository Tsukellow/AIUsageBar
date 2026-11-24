import Darwin
import Foundation

struct GrokUsageSnapshot: Sendable {
    let window: SubscriptionWindow?
    let prepaidCents: Int?
    let refreshedAt: Date
    private let periodKind: PeriodKind?

    var weeklyWindow: SubscriptionWindow? {
        self.periodKind == .weekly ? self.window : nil
    }

    var prepaidText: String? {
        guard let prepaidCents = self.prepaidCents, prepaidCents > 0 else { return nil }
        return String(format: "$%.2f", Double(prepaidCents) / 100)
    }

    static func decode(_ data: Data, refreshedAt: Date = .now) throws -> Self {
        let payload = try JSONDecoder().decode(Billing.self, from: data)
        let config = payload.config
        let period = config?.currentPeriod
        let kind = period?.type.flatMap(PeriodKind.init(rawValue:))
        let title = switch kind {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        default: "Subscription quota"
        }
        let end = SubscriptionUsage.date(period?.end) ?? SubscriptionUsage.date(config?.billingPeriodEnd)
        let window = config?.creditUsagePercent
            .flatMap { SubscriptionUsage.remainingFraction(used: $0, scale: 100) }
            .map { SubscriptionWindow(title: title, remainingFraction: $0, resetsAt: end) }
        let storedBalance = config?.prepaidBalance?.val
        let balance = storedBalance.flatMap { $0 >= 0 ? $0 : nil }
        guard window != nil || balance != nil else { throw GrokBillingError.noUsage }
        return Self(window: window, prepaidCents: balance, refreshedAt: refreshedAt, periodKind: kind)
    }

    private enum PeriodKind: String, Sendable {
        case weekly = "USAGE_PERIOD_TYPE_WEEKLY"
        case monthly = "USAGE_PERIOD_TYPE_MONTHLY"
    }

    private struct Billing: Decodable {
        let config: Config?
    }

    private struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
        let billingPeriodEnd: String?
        let prepaidBalance: Cent?

        enum CodingKeys: String, CodingKey { case creditUsagePercent, currentPeriod, billingPeriodEnd, prepaidBalance }

        init(from decoder: any Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            self.creditUsagePercent = try? box.decode(Double.self, forKey: .creditUsagePercent)
            self.currentPeriod = try? box.decode(Period.self, forKey: .currentPeriod)
            self.billingPeriodEnd = try? box.decode(String.self, forKey: .billingPeriodEnd)
            self.prepaidBalance = try? box.decode(Cent.self, forKey: .prepaidBalance)
        }
    }

    private struct Period: Decodable {
        let type: String?
        let end: String?
    }

    private struct Cent: Decodable {
        let val: Int

        init(from decoder: any Decoder) throws {
            // The official proto3 billing shape represents a zero Cent as {}.
            let box = try decoder.container(keyedBy: CodingKeys.self)
            self.val = box.contains(.val) ? try box.decode(Int.self, forKey: .val) : 0
        }

        enum CodingKeys: String, CodingKey { case val }
    }
}

enum GrokBillingError: LocalizedError {
    case missingCLI, launch, timeout, unsupported, login, unavailable, noUsage, invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCLI: "Grok Build CLI not found. Install it or select its executable in Settings."
        case .launch: "Could not start Grok Build CLI. Check the configured executable."
        case .timeout: "Grok Build CLI did not return usage in time."
        case .unsupported: "This Grok Build CLI does not expose subscription billing. Check for an update or open Grok Usage."
        case .login: "Sign in with your subscription account in Grok Build CLI, then refresh."
        case .unavailable: "Grok Build CLI could not read subscription usage. Check /usage in the CLI."
        case .noUsage: "Grok did not report a subscription quota or prepaid balance."
        case .invalidResponse: "Grok Build CLI returned an unrecognized billing response."
        }
    }
}

/// The official CLI owns authentication. Only the ACP initialize and read-only billing requests are sent.
@MainActor
final class GrokBillingCommand {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let executable: URL
    private let timeout: Duration
    private var continuation: CheckedContinuation<GrokUsageSnapshot, any Error>?
    private var deadline: Task<Void, Never>?
    private var buffer = Data()
    private var bytesRead = 0
    private var expectedID = 1

    init(executable: URL, timeout: Duration = .seconds(15)) {
        self.executable = executable
        self.timeout = timeout
    }

    func run() async throws -> GrokUsageSnapshot {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.launch()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func launch() {
        self.process.executableURL = self.executable
        self.process.arguments = ["agent", "stdio"]
        self.process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        for name in ["XAI_API_KEY", "GROK_API_KEY", "XAI_API_BASE", "XAI_BASE_URL", "GROK_BASE_URL"] {
            environment.removeValue(forKey: name)
        }
        self.process.environment = environment
        self.process.standardInput = self.input
        self.process.standardOutput = self.output
        self.process.standardError = FileHandle.nullDevice
        _ = fcntl(self.input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in self?.consume(data) }
        }
        do {
            try self.process.run()
            self.deadline = Task { [weak self, timeout = self.timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish(.failure(GrokBillingError.timeout))
            }
            try self.send([
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": ["protocolVersion": 1, "clientCapabilities": [:],
                           "clientInfo": ["name": "AIUsageBar", "version": "1.0"]],
            ])
        } catch {
            self.finish(.failure(GrokBillingError.launch))
        }
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        try self.input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard self.continuation != nil else { return }
        guard !data.isEmpty else {
            self.finish(.failure(GrokBillingError.unavailable))
            return
        }
        self.bytesRead += data.count
        guard self.bytesRead <= 512 * 1024 else {
            self.finish(.failure(GrokBillingError.invalidResponse))
            return
        }
        self.buffer.append(data)
        while let newline = self.buffer.firstIndex(of: 0x0A), self.continuation != nil {
            let line = self.buffer.prefix(upTo: newline)
            self.buffer.removeSubrange(...newline)
            guard let frame = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  frame["id"] as? Int == self.expectedID, frame["method"] == nil else { continue }
            if let error = frame["error"] as? [String: Any] {
                let code = error["code"] as? Int
                let message = (error["message"] as? String)?.lowercased() ?? ""
                let login = code == -32000 && (message.contains("auth") || message.contains("sign in"))
                    || message.contains("authentication required") || message.contains("not logged in")
                self.finish(.failure(code == -32601 ? GrokBillingError.unsupported : login ? .login : .unavailable))
                continue
            }
            guard let result = frame["result"] as? [String: Any] else {
                self.finish(.failure(GrokBillingError.invalidResponse))
                continue
            }
            do {
                if self.expectedID == 1 {
                    self.expectedID = 2
                    try self.send(["jsonrpc": "2.0", "id": 2, "method": "_x.ai/billing", "params": [:]])
                } else {
                    let payload = try JSONSerialization.data(withJSONObject: result)
                    self.finish(.success(try GrokUsageSnapshot.decode(payload)))
                }
            } catch let error as GrokBillingError {
                self.finish(.failure(error))
            } catch {
                self.finish(.failure(GrokBillingError.invalidResponse))
            }
        }
    }

    private func finish(_ result: Result<GrokUsageSnapshot, any Error>) {
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        self.deadline?.cancel()
        self.output.fileHandleForReading.readabilityHandler = nil
        try? self.input.fileHandleForWriting.close()
        if self.process.isRunning { self.process.terminate() }
        continuation.resume(with: result)
    }
}
