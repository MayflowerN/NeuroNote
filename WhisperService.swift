//
//  WhisperService.swift
//  NeuroNote
//
//  Created by Ellie on 7/4/25.
//

import Foundation
import SwiftData

struct WhisperService {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let apiKey = "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" // 🔐 Use Keychain in production

    static func transcribe(audioURL: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let formData = try createMultipartForm(audioURL: audioURL, boundary: boundary)
        request.httpBody = formData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let responseText = String(data: data, encoding: .utf8) ?? "N/A"
            print("❌ Whisper failed with status: \(httpResponse.statusCode)")
            print("🔍 Whisper response: \(responseText)")
            throw NSError(domain: "Whisper", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Whisper failed"])
        }
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }

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

struct WhisperResponse: Codable {
    let text: String
}
