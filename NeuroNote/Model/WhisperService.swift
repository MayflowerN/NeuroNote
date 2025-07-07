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

    /// Retrieves the Whisper API key from the Keychain. Crashes app if key is missing.
    static var apiKey: String {
        guard let key = KeychainHelper.load(key: "whisperAPIKey") else {
            fatalError("API Key not found in Keychain")
        }
        return key
    }

    /// Sends a .caf audio file to the Whisper API and returns the transcription text.
    /// Uses multipart/form-data for uploading audio. Validates response status and parses JSON.
    static func transcribe(audioURL: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let formData = try createMultipartForm(audioURL: audioURL, boundary: boundary)
        request.httpBody = formData

        // Performs the network request asynchronously.
        let (data, response) = try await URLSession.shared.data(for: request)

        // Ensure the response is an HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        // Throw error for failed status codes
        guard httpResponse.statusCode == 200 else {
            let responseText = String(data: data, encoding: .utf8) ?? "No response text"
            print("Whisper failed with status: \(httpResponse.statusCode)")
            print("Whisper response: \(responseText)")
            throw NSError(domain: "Whisper", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Whisper API failed"])
        }

        // Decode transcription result JSON into model
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }

    /// Constructs a multipart/form-data body for uploading an audio file to Whisper.
    private static func createMultipartForm(audioURL: URL, boundary: String) throws -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        // Part 1: Specify model name
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Part 2: Attach audio file
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.caf\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/x-caf\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: audioURL))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

/// Model for decoding Whisper API response text.
struct WhisperResponse: Codable {
    let text: String
}
