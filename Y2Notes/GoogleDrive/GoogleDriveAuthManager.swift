import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Manages Google OAuth 2.0 authorization using PKCE (Proof Key for Code Exchange).
///
/// This implementation uses `ASWebAuthenticationSession` which is the recommended
/// system API for OAuth flows on iOS — it handles the browser session, redirect URI,
/// and user consent without requiring the Google Sign-In SDK.
///
/// Tokens are persisted to the Keychain so they survive app restarts and device
/// migrations via encrypted backup.
final class GoogleDriveAuthManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var tokens: GoogleDriveTokens?
    @Published private(set) var userEmail: String?

    // MARK: - Configuration

    /// Google API OAuth 2.0 client ID for iOS.
    /// Replace with your project's client ID from the Google Cloud Console.
    static let clientID: String = {
        let id = "YOUR_CLIENT_ID.apps.googleusercontent.com"
        #if DEBUG
        if id.hasPrefix("YOUR_") {
            print("⚠️ [GoogleDriveAuthManager] Replace clientID with a real Google Cloud Console client ID before shipping.")
        }
        #endif
        return id
    }()
    /// Redirect URI registered in Google Cloud Console (custom scheme).
    static let redirectURI = "com.y2notes.app:/oauth2redirect"
    /// Scopes: Drive file access (read/write files created by the app) + user info email.
    static let scopes = "https://www.googleapis.com/auth/drive.file email"

    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private static let authEndpoint  = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"

    // Keychain service name for token storage.
    private static let keychainService = "com.y2notes.googleDriveTokens"
    private static let keychainAccount = "driveTokens"
    private static let keychainEmailAccount = "driveEmail"

    // PKCE verifier stored between auth initiation and token exchange.
    private var codeVerifier: String?

    // MARK: - Init

    override init() {
        super.init()
        loadTokensFromKeychain()
    }

    // MARK: - Auth flow

    /// Initiates the OAuth 2.0 + PKCE authorization flow using `ASWebAuthenticationSession`.
    ///
    /// - Parameter anchor: The window scene used to present the web authentication sheet.
    func startAuthFlow(anchor: ASPresentationAnchor) {
        let verifier  = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        codeVerifier  = verifier

        var components = URLComponents(string: Self.authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: Self.clientID),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: Self.scopes),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type",           value: "offline"),
            URLQueryItem(name: "prompt",                value: "consent"),
        ]

        guard let authURL = components.url else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.y2notes.app"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error {
                print("Y2Notes: Google auth cancelled or failed — \(error.localizedDescription)")
                return
            }
            guard let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }

            Task { @MainActor in
                await self.exchangeCodeForTokens(code)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Signs out: clears tokens from memory and Keychain.
    func signOut() {
        tokens = nil
        isAuthenticated = false
        userEmail = nil
        deleteFromKeychain(account: Self.keychainAccount)
        deleteFromKeychain(account: Self.keychainEmailAccount)
    }

    // MARK: - Token management

    /// Returns a valid access token, refreshing transparently if expired.
    func validAccessToken() async -> String? {
        guard var currentTokens = tokens else { return nil }
        if currentTokens.isExpired {
            guard await refreshAccessToken() else { return nil }
            currentTokens = tokens! // refreshed
        }
        return currentTokens.accessToken
    }

    // MARK: - Private: token exchange

    private func exchangeCodeForTokens(_ code: String) async {
        guard let verifier = codeVerifier else { return }
        codeVerifier = nil

        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "client_id=\(Self.clientID)",
            "redirect_uri=\(Self.redirectURI)",
            "grant_type=authorization_code",
            "code_verifier=\(verifier)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data)
            await fetchUserEmail()
        } catch {
            print("Y2Notes: Token exchange failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func refreshAccessToken() async -> Bool {
        guard let refresh = tokens?.refreshToken else { return false }

        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token=\(refresh)",
            "client_id=\(Self.clientID)",
            "grant_type=refresh_token",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            try handleTokenResponse(data, preserveRefresh: refresh)
            return true
        } catch {
            print("Y2Notes: Token refresh failed — \(error.localizedDescription)")
            return false
        }
    }

    private func handleTokenResponse(_ data: Data, preserveRefresh: String? = nil) throws {
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case accessToken  = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn    = "expires_in"
            }
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newTokens = GoogleDriveTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? preserveRefresh ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
        self.tokens = newTokens
        self.isAuthenticated = true
        saveTokensToKeychain(newTokens)
    }

    private func fetchUserEmail() async {
        guard let token = tokens?.accessToken else { return }
        var request = URLRequest(url: URL(string: Self.userInfoEndpoint)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct UserInfo: Decodable { let email: String? }
            let info = try JSONDecoder().decode(UserInfo.self, from: data)
            if let email = info.email {
                await MainActor.run {
                    self.userEmail = email
                }
                saveToKeychain(email.data(using: .utf8)!, account: Self.keychainEmailAccount)
            }
        } catch {
            // Non-critical; email display is cosmetic.
        }
    }

    // MARK: - PKCE helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keychain

    private func saveTokensToKeychain(_ tokens: GoogleDriveTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        saveToKeychain(data, account: Self.keychainAccount)
    }

    private func loadTokensFromKeychain() {
        if let data = loadFromKeychain(account: Self.keychainAccount),
           let stored = try? JSONDecoder().decode(GoogleDriveTokens.self, from: data) {
            self.tokens = stored
            self.isAuthenticated = true
        }
        if let emailData = loadFromKeychain(account: Self.keychainEmailAccount),
           let email = String(data: emailData, encoding: .utf8) {
            self.userEmail = email
        }
    }

    private func saveToKeychain(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        // Delete existing then add fresh — simplest idempotent approach.
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleDriveAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
