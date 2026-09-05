import Foundation
import Observation

@MainActor @Observable
final class AppSession {
    private(set) var serverURL: String
    private(set) var token = ""
    private(set) var vehicles: [Vehicle] = []
    private(set) var selectedVehicleID: Int?
    private(set) var connectionID = UUID()
    private(set) var isLoading = false
    private(set) var isConnecting = false
    private(set) var errorMessage: String?
    // Local fetch completion time, not the vehicle's observation time.
    private(set) var lastReceivedAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let fetch: (String, String) async throws -> [Vehicle]
    @ObservationIgnored private var connectionAttempt = UUID()

    init(defaults: UserDefaults = .standard,
         credentials: (any CredentialStore)? = nil,
         fetch: @escaping (String, String) async throws -> [Vehicle] = {
             try await APIClient(serverURL: $0, token: $1).vehicles()
         }) {
        self.defaults = defaults
        self.credentials = credentials ?? KeychainStore()
        self.fetch = fetch
        selectedVehicleID = defaults.object(forKey: "selectedVehicleID") as? Int
        serverURL = defaults.string(forKey: "serverURL") ?? ""
        do { token = try self.credentials.read() ?? "" }
        catch { errorMessage = error.localizedDescription }
    }

    var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }

    var selectedVehicle: Vehicle? { vehicles.first { $0.id == selectedVehicleID } }

    func selectVehicle(_ id: Int) {
        guard vehicles.contains(where: { $0.id == id }) else { return }
        selectedVehicleID = id
        defaults.set(id, forKey: "selectedVehicleID")
    }

    private func reconcileSelection() {
        if !vehicles.contains(where: { $0.id == selectedVehicleID }) {
            selectedVehicleID = vehicles.first?.id
        }
        if let selectedVehicleID { defaults.set(selectedVehicleID, forKey: "selectedVehicleID") }
        else { defaults.removeObject(forKey: "selectedVehicleID") }
    }

    func connect(serverURL: String, token: String) async throws {
        let normalized = try APIClient.normalizedServerURL(serverURL)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty,
              !trimmedToken.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw APIError.invalidToken
        }
        let attempt = UUID()
        connectionAttempt = attempt
        isConnecting = true
        defer { if connectionAttempt == attempt { isConnecting = false } }

        let result = try await fetch(normalized, trimmedToken)
        try Task.checkCancellation()
        guard connectionAttempt == attempt else { throw CancellationError() }
        // Verify first. A network or Keychain error leaves the current connection intact.
        try credentials.save(trimmedToken)
        defaults.set(normalized, forKey: "serverURL")
        connectionID = UUID()
        if self.serverURL != normalized || self.token != trimmedToken { selectedVehicleID = nil }
        self.serverURL = normalized
        self.token = trimmedToken
        vehicles = result
        reconcileSelection()
        lastReceivedAt = Date()
        errorMessage = nil
        isLoading = false
    }

    func disconnect() throws {
        try credentials.delete()
        connectionID = UUID()
        connectionAttempt = UUID()
        defaults.removeObject(forKey: "serverURL")
        serverURL = ""
        token = ""
        vehicles = []
        selectedVehicleID = nil
        defaults.removeObject(forKey: "selectedVehicleID")
        lastReceivedAt = nil
        errorMessage = nil
        isLoading = false
        isConnecting = false
    }

    func refresh() async {
        guard isConfigured, !isLoading else { return }
        let requestRevision = connectionID
        isLoading = true
        defer { if connectionID == requestRevision { isLoading = false } }
        do {
            let result = try await fetch(serverURL, token)
            try Task.checkCancellation()
            guard connectionID == requestRevision else { return }
            vehicles = result
            reconcileSelection()
            lastReceivedAt = Date()
            errorMessage = nil
        } catch {
            guard connectionID == requestRevision else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }
}
