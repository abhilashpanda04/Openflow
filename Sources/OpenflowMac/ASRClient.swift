import Foundation

struct TranscribeResponse: Decodable {
    let success: Bool?
    let language: String?
    let text: String
    let error: String?
}

struct HealthResponse: Decodable {
    let status: String
    let modelLoaded: Bool
    let modelName: String?
    let error: String?
    let authEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded = "model_loaded"
        case modelName = "model_name"
        case error
        case authEnabled = "auth_enabled"
    }
}

enum ASRClientError: LocalizedError {
    case badStatus(Int, String)
    case unauthorized
    case invalidResponse
    case emptyAudioFile
    case fileTooLarge(Int, Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "Server returned \(code): \(body)"
        case .unauthorized:
            return "Backend rejected request (invalid or missing API token)."
        case .invalidResponse:
            return "Invalid response from ASR server."
        case .emptyAudioFile:
            return "Audio file is empty."
        case .fileTooLarge(let size, let maxSize):
            return "Audio file is too large (\(size) bytes). Max allowed is \(maxSize) bytes."
        case .serverError(let message):
            return message
        }
    }
}

struct ASRClientConfiguration {
    let baseURL: URL
    let timeoutSeconds: TimeInterval
    let retryCount: Int
    let retryBaseDelayMs: Int
    let apiToken: String?
    let maxUploadBytes: Int
}

final class ASRClient {
    private let session: URLSession
    private let config: ASRClientConfiguration

    init(config: ASRClientConfiguration, session: URLSession? = nil) {
        self.config = config

        if let session {
            self.session = session
            return
        }

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = config.timeoutSeconds
        sessionConfiguration.timeoutIntervalForResource = config.timeoutSeconds
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func checkHealth(requestID: String = UUID().uuidString, completion: @escaping (Result<HealthResponse, Error>) -> Void) {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = config.timeoutSeconds

        if let token = config.apiToken {
            request.setValue(token, forHTTPHeaderField: "X-API-Token")
        }
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(ASRClientError.invalidResponse))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    completion(.failure(ASRClientError.unauthorized))
                    return
                }

                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                completion(.failure(ASRClientError.badStatus(httpResponse.statusCode, body)))
                return
            }

            do {
                let health = try JSONDecoder().decode(HealthResponse.self, from: data)
                completion(.success(health))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func transcribe(
        audioFileURL: URL,
        requestID: String = UUID().uuidString,
        completion: @escaping (Result<TranscribeResponse, Error>) -> Void
    ) {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = config.apiToken {
            request.setValue(token, forHTTPHeaderField: "X-API-Token")
        }
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")

        do {
            request.httpBody = try makeMultipartBody(fileURL: audioFileURL, boundary: boundary)
        } catch {
            completion(.failure(error))
            return
        }

        request.setValue(String(request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")

        executeWithRetry(request: request, attempt: 0, completion: completion)
    }

    private func executeWithRetry(
        request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<TranscribeResponse, Error>) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            if let error {
                if attempt < self.config.retryCount {
                    self.scheduleRetry(request: request, attempt: attempt, completion: completion)
                    return
                }

                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(ASRClientError.invalidResponse))
                return
            }

            if (500..<600).contains(httpResponse.statusCode), attempt < self.config.retryCount {
                self.scheduleRetry(request: request, attempt: attempt, completion: completion)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    completion(.failure(ASRClientError.unauthorized))
                    return
                }

                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                completion(.failure(ASRClientError.badStatus(httpResponse.statusCode, body)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(TranscribeResponse.self, from: data)

                if decoded.success == false {
                    completion(.failure(ASRClientError.serverError(decoded.error ?? "Transcription failed.")))
                    return
                }

                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func scheduleRetry(
        request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<TranscribeResponse, Error>) -> Void
    ) {
        let nextAttempt = attempt + 1
        let maxJitter = max(1, config.retryBaseDelayMs / 2)
        let jitter = Int.random(in: 0...maxJitter)
        let delayMs = (config.retryBaseDelayMs * (1 << attempt)) + jitter
        let delay = DispatchTimeInterval.milliseconds(delayMs)

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            self.executeWithRetry(request: request, attempt: nextAttempt, completion: completion)
        }
    }

    private func makeMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        let fileData = try Data(contentsOf: fileURL)
        if fileData.isEmpty {
            throw ASRClientError.emptyAudioFile
        }

        if fileData.count > config.maxUploadBytes {
            throw ASRClientError.fileTooLarge(fileData.count, config.maxUploadBytes)
        }

        let filename = fileURL.lastPathComponent

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append(lineBreak.data(using: .utf8)!)

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }
}
