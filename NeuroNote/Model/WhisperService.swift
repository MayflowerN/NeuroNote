//
//  WhisperService.swift
//  NeuroNote
//
//  Created by Ellie on 7/4/25.
//

import Foundation
import SwiftData

/// Handles audio transcription via OpenAI's Whisper API.
struct WhisperService {
    /// Whisper API endpoint URL.
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    /// Retrieves the Whisper API key from the Keychain.
    static var apiKey: String {
        guard let key = KeychainHelper.load(key: "whisperAPIKey") else {
            fatalError("API Key not found in Keychain")
        }
        return key
    }

    /// Sends a .caf audio file to Whisper API and returns the transcription.
    static func transcribe(audioURL: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let formData = try createMultipartForm(audioURL: audioURL, boundary: boundary)
        request.httpBody = formData

        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            let responseText = String(data: data, encoding: .utf8) ?? "No response text"
            print("Whisper failed with status: \(httpResponse.statusCode)")
            print("Whisper response: \(responseText)")
            throw NSError(domain: "Whisper", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Whisper API failed"])
        }

        // Parse response
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }

    /// Creates multipart/form-data body for audio file upload to Whisper.
    private static func createMultipartForm(audioURL: URL, boundary: String) throws -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.caf\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/x-caf\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: audioURL))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

/// Model for decoding Whisper API response.
struct WhisperResponse: Codable {
    let text: String
}
