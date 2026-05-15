//
//  LLMService.swift
//  StreamingDemo
//
//  Created by Sean on 5/14/26.
//

import Foundation

// MARK: - Error Types
enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case networkUnavailable
    case unauthorized       // 401
    case rateLimited        // 429
    case serverError(Int)   // 500+
    case decodingFailed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:     return "API key not configured"
        case .invalidURL:        return "Invalid API URL"
        case .networkUnavailable: return "Network unavailable. Please check your connection."
        case .unauthorized:      return "Invalid or expired API key"
        case .rateLimited:       return "Rate limit exceeded. Please try again shortly."
        case .serverError(let code): return "Server error (\(code))"
        case .decodingFailed:    return "Failed to parse response"
        case .unknown(let msg):  return msg
        }
    }
}

// MARK: - SSE Event Model
/// We only decode `content_block_delta` events; others are silently ignored.
private struct SSEDelta: Decodable {
    let type: String
    let delta: DeltaContent?
    
    struct DeltaContent: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - LLM Service
@MainActor
final class LLMService {
    
    private let baseURL = "https://api.deepseek.com/anthropic/v1/messages"
    private let model = "deepseek-v4-flash"  // Use Flash for dev; switch to Pro in production
    
    // MARK: - URLSession with custom timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10    // Fail fast if no response within 10s
        config.timeoutIntervalForResource = 120  // Hard cap for the entire stream
        config.waitsForConnectivity = false      // Don't wait for network to come back
        return URLSession(configuration: config)
    }()
    
    // MARK: - API Key
    private var apiKey: String {
        Bundle.main.infoDictionary?["DEEPSEEK_API_KEY"] as? String ?? ""
    }
    
    // MARK: - Public Entry Point
    /// Returns an AsyncThrowingStream that yields text deltas as they arrive.
    func streamMessage(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStream(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            // Propagate external cancellation down to the inner task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    // MARK: - HTTP + SSE Parsing
    private func performStream(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        
        // 1. Validate API key
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        // 2. Build URL
        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidURL
        }
        
        // 3. Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // 4. Fire the streaming request
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            // Network-level failure (offline, DNS, timeout, etc.)
            throw LLMError.networkUnavailable
        }
        
        // 5. Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.unknown("No HTTP response")
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            break  // OK, proceed to parse
        case 401:
            throw LLMError.unauthorized
        case 429:
            throw LLMError.rateLimited
        case 500...:
            throw LLMError.serverError(httpResponse.statusCode)
        default:
            throw LLMError.unknown("HTTP \(httpResponse.statusCode)")
        }
        
        // 6. Parse SSE line by line
        for try await line in bytes.lines {
            // Check cancellation on every line
            try Task.checkCancellation()
            
            // SSE format: only care about lines starting with "data: "
            guard line.hasPrefix("data: ") else { continue }
            
            let jsonString = String(line.dropFirst(6))  // strip "data: " prefix
            
            // End-of-stream marker (Anthropic SSE may or may not send this)
            if jsonString == "[DONE]" { break }
            
            guard let jsonData = jsonString.data(using: .utf8) else { continue }
            
            // Only decode content_block_delta; silently skip other event types
            guard let event = try? JSONDecoder().decode(SSEDelta.self, from: jsonData) else { continue }
            
            if event.type == "content_block_delta",
               let textChunk = event.delta?.text {
                continuation.yield(textChunk)
            }
        }
    }
}
