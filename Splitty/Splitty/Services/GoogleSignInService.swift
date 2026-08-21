//
//  GoogleSignInService.swift
//  Splitty
//
//  Created by Snowye on 20/08/26.
//

import Foundation
import GoogleSignIn
import UIKit

/// Wraps the Google SDK down to the one thing the API needs: a one-time `serverAuthCode`.
///
/// The app never holds a Google access or refresh token and there is no client secret on
/// the device — the code is redeemed server-side by `POST /oauth/google`.
///
/// `GIDClientID` and `GIDServerClientID` are read straight out of `Info.plist` by the SDK,
/// so there is no configuration step here.
final class GoogleSignInService {
    static let shared = GoogleSignInService()

    private init() {}

    /// Presents the Google account picker and returns the server auth code.
    ///
    /// Throws `GoogleSignInError.cancelled` when the user dismisses the sheet, so callers
    /// can stay silent about a deliberate dismiss.
    @MainActor
    func signIn() async throws -> String {
        guard let presenter = Self.topViewController() else {
            throw GoogleSignInError.noPresenter
        }

        let result: GIDSignInResult
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { signInResult, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let signInResult {
                        continuation.resume(returning: signInResult)
                    } else {
                        continuation.resume(throwing: GoogleSignInError.failed)
                    }
                }
            }
        } catch {
            if let signInError = error as? GIDSignInError, signInError.code == .canceled {
                throw GoogleSignInError.cancelled
            }
            throw GoogleSignInError.failed
        }

        // Only present when `GIDServerClientID` is set; a nil code means the plist is wrong.
        guard let authCode = result.serverAuthCode else {
            throw GoogleSignInError.missingAuthCode
        }

        return authCode
    }

    /// Completes a sign-in redirect handed back to the app by the custom URL scheme.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }

        while let presented = top.presentedViewController {
            top = presented
        }

        return top
    }
}

enum GoogleSignInError: Error {
    /// The user dismissed the account picker. Not surfaced to the user.
    case cancelled
    case noPresenter
    case missingAuthCode
    case failed
}
