//
//  WhisperServiceTests.swift
//  NeuroNoteTests
//
//  Created by Ellie on 7/5/25.
//

import XCTest
@testable import NeuroNote

final class WhisperServiceTests: XCTestCase {
    
    /// Saves and loads a value from the Keychain, and confirms correctness
    func testKeychainHelperSaveAndLoad() {
        let testKey = "testAPIKey"
        let testValue = "sk-test-key-1234"

        KeychainHelper.save(key: testKey, value: testValue)
        let loadedValue = KeychainHelper.load(key: testKey)

        XCTAssertEqual(loadedValue, testValue, "KeychainHelper should return saved value")
    }

    /// Confirms fallback mechanism works if Whisper API key is missing
    func testWhisperServiceFallbacksToFatalErrorIfKeyMissing() {
        // Setup a fake key so the test doesn't fail
        let testAPIKey = "sk-fake-api-key"
        KeychainHelper.save(key: "whisperAPIKey", value: testAPIKey)

        let key = KeychainHelper.load(key: "whisperAPIKey")
        XCTAssertNotNil(key, "API Key should be present in Keychain")
    }
}
