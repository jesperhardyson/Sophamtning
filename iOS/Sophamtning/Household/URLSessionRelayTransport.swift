import Foundation
import SophamtningKit

/// Nätet mot brevlådan: anrop med HTTPS, och en WebSocket som säger till när något har ändrats.
struct URLSessionRelayTransport: RelayTransport {
    private static let base = "https://hushall.sopor.hardyson.se/v1"
    /// Hur ofta uppkopplingen prövas, så att en som har dött i tysthet upptäcks.
    private static let pingInterval: Duration = .seconds(30)

    private let session: URLSession
    private let userAgent: String

    init(version: String) {
        userAgent = "Sophamtning-iOS/\(version)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: RelayRequest) async throws -> RelayResponse {
        guard let url = URL(string: Self.base + request.path) else { throw URLError(.badURL) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return RelayResponse(status: response.statusCode, body: data)
    }

    func signals(householdId: String, authorization: String) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task {
                var failures = 0
                while !Task.isCancelled {
                    if await listen(householdId: householdId, authorization: authorization, to: continuation) { failures = 0 }
                    failures += 1
                    try? await Task.sleep(for: RelayBackoff.delay(attempt: failures))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Signal: Decodable {
        let seq: Int
    }

    /// Lyssnar tills uppkopplingen bryts. Svarar med om den någonsin kom upp.
    private func listen(householdId: String, authorization: String, to continuation: AsyncStream<Int>.Continuation) async -> Bool {
        guard let url = URL(string: "\(Self.base)/households/\(householdId)/socket") else { return false }
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return await withTaskCancellationHandler {
            guard await ping(socket) else {
                reportLoss(of: socket, to: continuation)
                socket.cancel()
                return false
            }
            // Ändringar kan ha missats medan uppkopplingen var nere.
            continuation.yield(0)
            let pinging = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pingInterval)
                    if Task.isCancelled { return }
                    if await !ping(socket) {
                        socket.cancel()
                        return
                    }
                }
            }
            while let message = try? await socket.receive() {
                let data: Data? = switch message {
                case .string(let text): Data(text.utf8)
                case .data(let data): data
                @unknown default: nil
                }
                if let data, let signal = try? JSONDecoder().decode(Signal.self, from: data) { continuation.yield(signal.seq) }
            }
            pinging.cancel()
            reportLoss(of: socket, to: continuation)
            socket.cancel()
            return true
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Säger till när servern stängde för att hushållet är borta, så att appen hämtar i stället för att bara koppla upp igen.
    private func reportLoss(of socket: URLSessionWebSocketTask, to continuation: AsyncStream<Int>.Continuation) {
        let status = (socket.response as? HTTPURLResponse)?.statusCode
        if RelayClose.mayHaveLostHousehold(closeCode: socket.closeCode.rawValue, status: status) { continuation.yield(0) }
    }

    private func ping(_ socket: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            // Svaret kan komma mer än en gång när uppkopplingen bryts.
            let answered = OnceFlag()
            socket.sendPing { error in
                if answered.claim() { continuation.resume(returning: error == nil) }
            }
        }
    }
}

/// Släpper fram bara den första.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
