import Foundation
import Security

public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    /// Sends one prompt and returns the model's text reply.
    func complete(system: String, user: String) async throws -> String
}

public enum AIError: Error, CustomStringConvertible {
    case badEndpoint(String)
    case http(Int, String)
    case unexpectedReply(String)
    case missingKey(AIProviderKind)

    public var description: String {
        switch self {
        case .badEndpoint(let text): return "Not a valid address: \(text)"
        case .http(let code, let body): return "The AI service answered \(code): \(body.prefix(300))"
        case .unexpectedReply(let text): return "Could not understand the AI reply: \(text.prefix(300))"
        case .missingKey(let kind): return "\(kind.displayName) needs an API key (saved in the Keychain)."
        }
    }
}

/// Sends HTTP requests; swappable in tests so nothing goes over the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// One provider type speaking the four supported APIs.
public struct HTTPAIProvider: AIProvider {
    public let kind: AIProviderKind
    public var endpoint: String
    public var model: String
    public var apiKey: String?
    public var transport: any HTTPTransport

    public init(kind: AIProviderKind, endpoint: String, model: String, apiKey: String?, transport: any HTTPTransport = URLSessionTransport()) {
        self.kind = kind
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.transport = transport
    }

    public func makeRequest(system: String, user: String) throws -> URLRequest {
        let base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let path: String
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]
        switch kind {
        case .ollama:
            path = "/api/chat"
            body = ["model": model, "stream": false, "format": "json",
                    "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        case .openai:
            path = "/chat/completions"
            if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
            body = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        case .anthropic:
            path = "/v1/messages"
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingKey(kind) }
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = ["model": model, "max_tokens": 2048, "system": system, "messages": [["role": "user", "content": user]]]
        case .gemini:
            path = "/v1beta/models/\(model):generateContent"
            guard let apiKey, !apiKey.isEmpty else { throw AIError.missingKey(kind) }
            headers["x-goog-api-key"] = apiKey
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": user]]]],
                    "generationConfig": ["responseMimeType": "application/json"]]
        }
        guard let url = URL(string: base + path), url.scheme?.hasPrefix("http") == true else { throw AIError.badEndpoint(endpoint) }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func complete(system: String, user: String) async throws -> String {
        let (data, status) = try await transport.send(try makeRequest(system: system, user: user))
        let text = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(status) else { throw AIError.http(status, text) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.unexpectedReply(text) }
        let reply: String?
        switch kind {
        case .ollama:
            reply = (json["message"] as? [String: Any])?["content"] as? String
        case .openai:
            reply = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        case .anthropic:
            reply = (json["content"] as? [[String: Any]])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        case .gemini:
            let candidate = (json["candidates"] as? [[String: Any]])?.first
            reply = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        }
        guard let reply else { throw AIError.unexpectedReply(text) }
        return reply
    }
}

/// API keys live only in the login Keychain.
public enum KeychainStore {
    private static let service = "TidyUpMyFiles AI"

    public static func key(for kind: AIProviderKind) -> String? {
        read(kind, service: service)
    }

    private static func read(_ kind: AIProviderKind, service: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: kind.rawValue, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func setKey(_ key: String?, for kind: AIProviderKind) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: kind.rawValue]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
