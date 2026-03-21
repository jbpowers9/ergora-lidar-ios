//
//  ErgoraAPIClient.swift
//  ErgoraLiDAR
//

import Foundation

enum ErgoraAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, message: String?)
    case decodingFailed
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Request failed with status \(code)."
        case .decodingFailed:
            return "Could not read the server response."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

struct ErgoraAPIClient {
    private static let baseURL = URL(string: "https://ergora.ai/api/reports")!

    private struct APIErrorBody: Decodable {
        let error: String
    }

    static func submitSketch(reportId: UUID, token: String, payload: SketchPayload) async -> Result<Void, ErgoraAPIError> {
        let url = Self.baseURL.appendingPathComponent("\(reportId.uuidString)/sketch/import")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "X-Ergora-Scan")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            return .failure(.transport(error))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.httpStatus(-1, message: nil))
            }
            guard (200...299).contains(http.statusCode) else {
                let message = decodeErrorMessage(from: data)
                return .failure(.httpStatus(http.statusCode, message: message))
            }
            return .success(())
        } catch {
            return .failure(.transport(error))
        }
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return body.error
        }
        return String(data: data, encoding: .utf8)
    }
}
