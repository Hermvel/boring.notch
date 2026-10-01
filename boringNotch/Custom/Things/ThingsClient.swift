//
//  ThingsClient.swift
//  boringNotch
//
//  Minimal MCP (JSON-RPC over HTTP) client for the self-hosted Things Cloud MCP server.
//  The server is stateless: every request is a plain POST of a `tools/call` message,
//  and the tool result comes back as JSON text inside `result.content[0].text`.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ThingsTask: Identifiable, Decodable, Hashable {
    let uuid: String
    let title: String
    let note: String?
    let status: String?
    let scheduledFor: String?
    let deadline: String?
    let projectID: String?
    let areaID: String?
    let tags: [String]?

    var id: String { uuid }
    /// The server also returns canceled tasks; only open ones are shown.
    var isOpen: Bool { status == nil || status == "open" }

    /// Things stores "no deadline" as the far-future date 4001-01-01.
    var realDeadline: String? {
        guard let deadline, !deadline.hasPrefix("4001") else { return nil }
        return deadline
    }

    enum CodingKeys: String, CodingKey {
        case uuid, title, note, status, deadline, tags
        case scheduledFor = "scheduled_for"
        case projectID = "project_id"
        case areaID = "area_id"
    }
}

/// An area or a project — both come back as `{uuid, title}`.
struct ThingsContainer: Identifiable, Decodable, Hashable {
    let uuid: String
    let title: String
    var id: String { uuid }
}

enum ThingsClientError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Укажите адрес сервера Things в настройках"
        case .badURL: return "Неверный адрес сервера"
        case .http(let code): return "Сервер ответил кодом \(code)"
        case .server(let message): return message
        case .decoding(let message): return "Не удалось разобрать ответ: \(message)"
        }
    }
}

final class ThingsClient: @unchecked Sendable {
    private let session: URLSession
    private var requestID = 0
    private let lock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    func listTasks(tool: String, arguments: [String: Any] = [:], serverURL: String, token: String) async throws -> [ThingsTask] {
        var args = arguments
        if args["limit"] == nil { args["limit"] = 500 }
        let text = try await callTool(tool, arguments: args, serverURL: serverURL, token: token)
        return try decode([ThingsTask].self, from: text)
    }

    func listContainers(tool: String, serverURL: String, token: String) async throws -> [ThingsContainer] {
        let text = try await callTool(tool, arguments: ["limit": 200], serverURL: serverURL, token: token)
        return try decode([ThingsContainer].self, from: text)
    }

    func setCompleted(_ completed: Bool, uuid: String, serverURL: String, token: String) async throws {
        let tool = completed ? "things_complete_task" : "things_uncomplete_task"
        _ = try await callTool(tool, arguments: ["uuid": uuid], serverURL: serverURL, token: token)
    }

    // MARK: - JSON-RPC

    func callTool(_ name: String, arguments: [String: Any], serverURL: String, token: String) async throws -> String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThingsClientError.notConfigured }
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else { throw ThingsClientError.badURL }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextID(),
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ]

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ThingsClientError.http(http.statusCode)
        }
        return try Self.extractText(from: Self.unwrapSSE(data))
    }

    private func nextID() -> Int {
        lock.lock(); defer { lock.unlock() }
        requestID += 1
        return requestID
    }

    /// Some MCP servers answer with `text/event-stream`; take the last `data:` line in that case.
    static func unwrapSSE(_ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8),
              string.hasPrefix("event:") || string.hasPrefix("data:") else { return data }
        let payload = string
            .split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .last
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        return payload?.data(using: .utf8) ?? data
    }

    static func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThingsClientError.decoding("not a JSON object")
        }
        if let error = json["error"] as? [String: Any] {
            throw ThingsClientError.server(error["message"] as? String ?? "Unknown server error")
        }
        guard let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]] else {
            throw ThingsClientError.decoding("missing result.content")
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        if result["isError"] as? Bool == true {
            throw ThingsClientError.server(text.isEmpty ? "Tool error" : text)
        }
        return text
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        // Empty lists sometimes come back as a plain message instead of "[]".
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{") else {
            if let empty = [] as? T { return empty }
            throw ThingsClientError.decoding(trimmed)
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(trimmed.utf8))
        } catch {
            throw ThingsClientError.decoding(error.localizedDescription)
        }
    }
}
