//
//  LoginView.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import SwiftUI

struct LoginView: View {
    @State private var isLoading = false
    @State private var errorMessage = ""
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some View {
        ZStack {
            // Simple black background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brand Section
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)

                    Text("Splitty")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    // Says what the app is before it asks for an account.
                    Text("Split expenses, settle up.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
                Spacer()

                // Providers
                VStack(spacing: 16) {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }

                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                GoogleMark()
                                    .frame(width: 18, height: 18)

                                // Google brand guidelines require this exact string.
                                Text("Sign in with Google")
                                    .fontWeight(.medium)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(25)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 20)

                    // Placeholder until Apple credentials exist. Sign in with Apple is
                    // mandatory for App Store review once any third-party provider ships,
                    // so this is a submission blocker, not a nice-to-have.
                    VStack(spacing: 6) {
                        Button {
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                Text("Sign in with Apple")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(25)
                        }
                        .disabled(true)
                        .opacity(0.4)

                        Text("Coming soon")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 20)

                    #if DEBUG
                    DevSignInPicker(isLoading: $isLoading, errorMessage: $errorMessage)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    #endif
                }
                .padding(.bottom, 50)
            }
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let user = try await AuthService.shared.signInWithGoogle()
            print("✅ Sign-in successful for user: \(user.name)")
            authManager.login()
        } catch GoogleSignInError.cancelled {
            // Dismissing the sheet is deliberate; nothing to report.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Never surfaces a raw `localizedDescription` from the SDK or a 500.
    static func message(for error: Error) -> String {
        if let signInError = error as? GoogleSignInError {
            switch signInError {
            case .missingAuthCode, .noPresenter:
                return "Sign-in isn't set up correctly on this build."
            case .cancelled, .failed:
                return "Sign-in failed. Try again."
            }
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(401):
                return "Google couldn't verify that account. Try again."
            case .httpError, .decodingError, .invalidResponse:
                return "Something went wrong signing you in. Try again in a moment."
            case .networkError:
                return "Couldn't reach Splitty. Check your connection and try again."
            default:
                return "Sign-in isn't set up correctly on this build."
            }
        }

        return "Sign-in failed. Try again."
    }
}

/// The Google "G" in its four brand colours, drawn rather than bundled so there is no
/// image asset to keep in sync with the SDK.
private struct GoogleMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.25)
                    .stroke(Color(red: 0.92, green: 0.26, blue: 0.21), lineWidth: size * 0.22)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0.25, to: 0.5)
                    .stroke(Color(red: 0.98, green: 0.74, blue: 0.02), lineWidth: size * 0.22)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0.5, to: 0.75)
                    .stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: size * 0.22)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0.75, to: 1.0)
                    .stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: size * 0.22)
                    .rotationEffect(.degrees(-90))

                Rectangle()
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: size * 0.5, height: size * 0.22)
                    .offset(x: size * 0.25, y: 0)
            }
            .frame(width: size, height: size)
        }
    }
}

#if DEBUG
/// A picker rather than a single button: testing splits and balances means signing in as
/// a *different* member of the same seeded group.
private struct DevSignInPicker: View {
    private static let seededEmails = [
        "john@example.com",
        "jane@example.com",
        "bob@example.com",
        "alice@example.com",
        "charlie@example.com",
        "eva@example.com"
    ]

    @Binding var isLoading: Bool
    @Binding var errorMessage: String
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some View {
        Menu {
            ForEach(Self.seededEmails, id: \.self) { email in
                Button(email) {
                    Task { await devSignIn(email: email) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "hammer")
                Text("Dev sign in")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.white)
            .cornerRadius(25)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }

    @MainActor
    private func devSignIn(email: String) async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let user = try await AuthService.shared.devSignIn(email: email)
            print("✅ Dev sign-in successful for user: \(user.name)")
            authManager.login()
        } catch {
            errorMessage = LoginView.message(for: error)
        }
    }
}
#endif

#Preview {
    LoginView()
}
