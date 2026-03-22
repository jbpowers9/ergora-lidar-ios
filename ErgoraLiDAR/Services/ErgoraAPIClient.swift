//
//  ErgoraAPIClient.swift
//  ErgoraLiDAR
//
//  Scan session tokens are issued by the Ergora web app (see Next.js `scan-token` route). There is no
//  token-refresh API on device; a new QR scan is required after expiry. Server-side expiry is configured
//  in the web repo (team note: consider extending past 15 minutes, e.g. 60 minutes, in `scan-token/route.ts`).

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

    /// POST multipart `photo` to `https://ergora.ai/api/reports/{id}/photos`.
    static func uploadInteriorPhoto(
        reportId: UUID,
        token: String,
        imageJPEGData: Data,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Result<Void, ErgoraAPIError> {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartJPEGBody(data: imageJPEGData, boundary: boundary)

        let url = Self.baseURL.appendingPathComponent("\(reportId.uuidString)/photos")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "X-Ergora-Scan")

        let delegate = MultipartUploadDelegate(onProgress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)

        do {
            progress(0)
            let (data, response) = try await session.upload(for: request, from: body)
            progress(1)
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

    private static func multipartJPEGBody(data: Data, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n".data(using: .utf8)!
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append(crlf)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private final class MultipartUploadDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
