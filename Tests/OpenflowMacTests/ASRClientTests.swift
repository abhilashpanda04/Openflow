// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import XCTest
@testable import OpenflowMac

private enum MockProtocolError: Error {
    case missingStub
}

private final class MockURLProtocol: URLProtocol {
    struct Stub {
        let response: HTTPURLResponse?
        let data: Data?
        let error: Error?
    }

    private static let lock = NSLock()
    private static var stubs: [Stub] = []
    private static var requests: [URLRequest] = []

    static func configure(stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        self.stubs = stubs
        requests = []
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mock.openflow.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub?
        Self.lock.lock()
        Self.requests.append(request)
        if Self.stubs.isEmpty {
            stub = nil
        } else {
            stub = Self.stubs.removeFirst()
        }
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: MockProtocolError.missingStub)
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = stub.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ASRClientTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        MockURLProtocol.configure(stubs: [])
    }

    override func tearDown() {
        for file in tempFiles {
            try? FileManager.default.removeItem(at: file)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    func testCheckHealthSuccessDecodesResponse() {
        let url = URL(string: "http://mock.openflow.local/health")!
        MockURLProtocol.configure(stubs: [
            makeStub(
                url: url,
                statusCode: 200,
                json: """
                {"status":"ok","model_loaded":true,"model_name":"Qwen","auth_enabled":true}
                """
            )
        ])

        let client = makeClient()
        let result: Result<HealthResponse, Error> = awaitResult { completion in
            client.checkHealth(requestID: "health-req", completion: completion)
        }

        switch result {
        case .success(let health):
            XCTAssertEqual(health.status, "ok")
            XCTAssertTrue(health.modelLoaded)
            XCTAssertEqual(health.modelName, "Qwen")
            XCTAssertEqual(health.authEnabled, true)
        case .failure(let error):
            XCTFail("Expected success but got \(error)")
        }

        let request = tryGetSingleRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/health")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Token"), "token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "health-req")
    }

    func testCheckHealthUnauthorizedReturnsSpecificError() {
        let url = URL(string: "http://mock.openflow.local/health")!
        MockURLProtocol.configure(stubs: [
            makeStub(url: url, statusCode: 401, json: "{\"error\":\"unauthorized\"}")
        ])

        let client = makeClient()
        let result: Result<HealthResponse, Error> = awaitResult { completion in
            client.checkHealth(requestID: "health-401", completion: completion)
        }

        assertError(result, matches: .unauthorized)
    }

    func testCheckHealthNon2xxReturnsBadStatus() {
        let url = URL(string: "http://mock.openflow.local/health")!
        MockURLProtocol.configure(stubs: [
            makeStub(url: url, statusCode: 503, json: "{\"error\":\"down\"}")
        ])

        let client = makeClient()
        let result: Result<HealthResponse, Error> = awaitResult { completion in
            client.checkHealth(requestID: "health-503", completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard case .badStatus(let code, let body) = error as? ASRClientError else {
                XCTFail("Expected badStatus but got \(error)")
                return
            }
            XCTAssertEqual(code, 503)
            XCTAssertTrue(body.contains("down"))
        }
    }

    func testTranscribeRejectsEmptyAudioFile() throws {
        let audioURL = try makeTempAudioFile(data: Data())
        let client = makeClient()

        let result: Result<TranscribeResponse, Error> = awaitResult { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "empty", completion: completion)
        }

        assertError(result, matches: .emptyAudioFile)
        XCTAssertTrue(MockURLProtocol.capturedRequests().isEmpty)
    }

    func testTranscribeRejectsOversizedAudioFile() throws {
        let audioURL = try makeTempAudioFile(data: Data("abc".utf8))
        let client = makeClient(maxUploadBytes: 2)

        let result: Result<TranscribeResponse, Error> = awaitResult { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "too-large", completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard case .fileTooLarge(let size, let maxSize) = error as? ASRClientError else {
                XCTFail("Expected fileTooLarge but got \(error)")
                return
            }
            XCTAssertEqual(size, 3)
            XCTAssertEqual(maxSize, 2)
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests().isEmpty)
    }

    func testTranscribeSuccessBuildsMultipartRequestAndDecodesResponse() throws {
        let audioURL = try makeTempAudioFile(data: Data("audio".utf8))
        let endpoint = URL(string: "http://mock.openflow.local/transcribe")!
        MockURLProtocol.configure(stubs: [
            makeStub(url: endpoint, statusCode: 200, json: #"{"success":true,"language":"en","text":"hello"}"#)
        ])

        let client = makeClient()
        let result: Result<TranscribeResponse, Error> = awaitResult { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "tx-success", completion: completion)
        }

        switch result {
        case .success(let response):
            XCTAssertEqual(response.text, "hello")
            XCTAssertEqual(response.language, "en")
            XCTAssertEqual(response.success, true)
        case .failure(let error):
            XCTFail("Expected success but got \(error)")
        }

        let request = tryGetSingleRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/transcribe")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Token"), "token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "tx-success")

        let contentType = request.value(forHTTPHeaderField: "Content-Type")
        XCTAssertNotNil(contentType)
        XCTAssertTrue(contentType?.contains("multipart/form-data") == true)

        let body = String(decoding: requestBodyData(from: request), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"audio\"; filename=\"\(audioURL.lastPathComponent)\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("audio"))
        XCTAssertFalse(body.isEmpty)
    }

    func testTranscribeMapsServerFailurePayloadToServerError() throws {
        let audioURL = try makeTempAudioFile(data: Data("audio".utf8))
        let endpoint = URL(string: "http://mock.openflow.local/transcribe")!
        MockURLProtocol.configure(stubs: [
            makeStub(
                url: endpoint,
                statusCode: 200,
                json: #"{"success":false,"text":"","error":"model busy"}"#
            )
        ])

        let client = makeClient()
        let result: Result<TranscribeResponse, Error> = awaitResult { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "tx-server-fail", completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard case .serverError(let message) = error as? ASRClientError else {
                XCTFail("Expected serverError but got \(error)")
                return
            }
            XCTAssertEqual(message, "model busy")
        }
    }

    func testTranscribeRetriesOnServerErrorAndThenSucceeds() throws {
        let audioURL = try makeTempAudioFile(data: Data("audio".utf8))
        let endpoint = URL(string: "http://mock.openflow.local/transcribe")!
        MockURLProtocol.configure(stubs: [
            makeStub(url: endpoint, statusCode: 503, json: #"{"error":"retry"}"#),
            makeStub(url: endpoint, statusCode: 200, json: #"{"success":true,"text":"after retry"}"#),
        ])

        let client = makeClient(retryCount: 1, retryBaseDelayMs: 1)
        let result: Result<TranscribeResponse, Error> = awaitResult(timeout: 3) { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "tx-retry", completion: completion)
        }

        switch result {
        case .success(let response):
            XCTAssertEqual(response.text, "after retry")
        case .failure(let error):
            XCTFail("Expected success after retry but got \(error)")
        }

        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 2)
    }

    func testTranscribeReturnsUnauthorizedWithoutRetrying() throws {
        let audioURL = try makeTempAudioFile(data: Data("audio".utf8))
        let endpoint = URL(string: "http://mock.openflow.local/transcribe")!
        MockURLProtocol.configure(stubs: [
            makeStub(url: endpoint, statusCode: 401, json: #"{"error":"unauthorized"}"#),
            makeStub(url: endpoint, statusCode: 200, json: #"{"success":true,"text":"unexpected"}"#),
        ])

        let client = makeClient(retryCount: 2, retryBaseDelayMs: 1)
        let result: Result<TranscribeResponse, Error> = awaitResult { completion in
            client.transcribe(audioFileURL: audioURL, requestID: "tx-401", completion: completion)
        }

        assertError(result, matches: .unauthorized)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)
    }

    private func makeClient(
        retryCount: Int = 0,
        retryBaseDelayMs: Int = 1,
        maxUploadBytes: Int = 4096
    ) -> ASRClient {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        sessionConfiguration.timeoutIntervalForRequest = 1
        sessionConfiguration.timeoutIntervalForResource = 1
        let session = URLSession(configuration: sessionConfiguration)

        let config = ASRClientConfiguration(
            baseURL: URL(string: "http://mock.openflow.local")!,
            timeoutSeconds: 1,
            retryCount: retryCount,
            retryBaseDelayMs: retryBaseDelayMs,
            apiToken: "token-123",
            maxUploadBytes: maxUploadBytes
        )
        return ASRClient(config: config, session: session)
    }

    private func makeTempAudioFile(data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openflow-test-\(UUID().uuidString).wav")
        try data.write(to: fileURL)
        tempFiles.append(fileURL)
        return fileURL
    }

    private func makeStub(url: URL, statusCode: Int, json: String) -> MockURLProtocol.Stub {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        return MockURLProtocol.Stub(response: response, data: Data(json.utf8), error: nil)
    }

    private func awaitResult<T>(
        timeout: TimeInterval = 2,
        _ operation: (@escaping (Result<T, Error>) -> Void) -> Void
    ) -> Result<T, Error> {
        let expectation = expectation(description: "async result")
        var captured: Result<T, Error>?
        operation { result in
            captured = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        guard let captured else {
            XCTFail("Expected result before timeout")
            return .failure(MockProtocolError.missingStub)
        }
        return captured
    }

    private func assertError<T>(_ result: Result<T, Error>, matches expected: ASRClientError) {
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard let asrError = error as? ASRClientError else {
                XCTFail("Expected ASRClientError but got \(error)")
                return
            }
            XCTAssertEqual(String(describing: asrError), String(describing: expected))
        }
    }

    private func tryGetSingleRequest() -> URLRequest {
        let requests = MockURLProtocol.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        guard let request = requests.first else {
            return URLRequest(url: URL(string: "http://invalid.local")!)
        }
        return request
    }

    private func requestBodyData(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
