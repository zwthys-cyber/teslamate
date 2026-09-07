import Security
import XCTest
@testable import TeslaMateMobile

final class KeychainStoreTests: XCTestCase {
    @MainActor
    func testNativeKeychainInsertUpdateReadAndDelete() async throws {
        let service = "com.zwthys.teslamate.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        defer { try? store.delete() }
        XCTAssertNil(try store.read())
        try store.save("first-test-token")
        XCTAssertEqual(try store.read(), "first-test-token")
        try store.save("updated-test-token")
        XCTAssertEqual(try store.read(), "updated-test-token")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try store.delete()
        XCTAssertNil(try store.read())
        try store.delete()
    }
}
