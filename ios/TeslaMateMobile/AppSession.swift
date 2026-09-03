import Foundation
import Observation

@MainActor @Observable
final class AppSession {
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.88.30.82:4000/"
    var token = KeychainStore.read(account: "apiToken") ?? ""
    var vehicles: [Vehicle] = []
    var isLoading = false
    var errorMessage: String?

    var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }

    func save(serverURL: String, token: String) {
        var normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasSuffix("/") { normalized += "/" }
        self.serverURL = normalized
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(normalized, forKey: "serverURL")
        KeychainStore.save(self.token, account: "apiToken")
    }

    func refresh() async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            vehicles = try await APIClient(serverURL: serverURL, token: token).vehicles()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
