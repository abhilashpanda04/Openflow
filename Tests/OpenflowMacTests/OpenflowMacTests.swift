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

import XCTest
@testable import OpenflowMac

final class OpenflowMacTests: XCTestCase {
    func testASRClientErrorDescriptions() {
        XCTAssertEqual(ASRClientError.badStatus(418, "teapot").errorDescription, "Server returned 418: teapot")
        XCTAssertEqual(ASRClientError.unauthorized.errorDescription, "Backend rejected request (invalid or missing API token).")
        XCTAssertEqual(ASRClientError.invalidResponse.errorDescription, "Invalid response from ASR server.")
        XCTAssertEqual(ASRClientError.emptyAudioFile.errorDescription, "Audio file is empty.")
        XCTAssertEqual(
            ASRClientError.fileTooLarge(1025, 1024).errorDescription,
            "Audio file is too large (1025 bytes). Max allowed is 1024 bytes."
        )
        XCTAssertEqual(ASRClientError.serverError("boom").errorDescription, "boom")
    }

    func testBackendSupervisorErrorDescriptions() {
        XCTAssertEqual(BackendSupervisorError.alreadyRunning.errorDescription, "Backend process is already running.")
        XCTAssertEqual(BackendSupervisorError.backendDirectoryNotFound.errorDescription, "Could not locate backend directory.")
        XCTAssertEqual(
            BackendSupervisorError.bundledRuntimeNotFound.errorDescription,
            "Bundled backend runtime is unavailable. Reinstall Openflow or use manual backend setup."
        )
        XCTAssertEqual(
            BackendSupervisorError.launcherUnavailable.errorDescription,
            "Could not find a backend launcher (bundled runtime, uv, or backend/.venv/bin/python)."
        )
        XCTAssertEqual(BackendSupervisorError.launchFailed("oops").errorDescription, "oops")
    }

    func testAudioRecorderErrorDescriptions() {
        XCTAssertEqual(AudioRecorderError.micPermissionDenied.errorDescription, "Microphone permission was denied.")
        XCTAssertEqual(AudioRecorderError.recorderCreationFailed.errorDescription, "Failed to create audio recorder.")
    }
}
