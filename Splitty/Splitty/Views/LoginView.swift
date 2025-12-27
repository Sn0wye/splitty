//
//  LoginView.swift
//  Splitty
//
//  Created by Snowye on 21/09/25.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        ZStack {
            // Simple black background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Logo and Title Section
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("Hello.")
                        .font(.largeTitle)
                        .fontWeight(.regular)
                        .foregroundColor(.white)
                    
                    Spacer()
                    Spacer()
                }
                
                // Login Form
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .textContentType(.password)
                    }
                    
                    // Error Message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                    
                    // Login Button
                    Button(action: login) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Continue")
                                    .fontWeight(.medium)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(25)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Mock User Button (Temporary)
                    Button(action: loginWithMockUser) {
                        HStack {
                            Image(systemName: "person.circle")
                            Text("Login as John")
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
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.bottom, 50)
            }
        }
    }
    
    private func login() {
        isLoading = true
        errorMessage = ""
        
        AuthService.shared.login(email: email, password: password) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let user):
                    print("✅ Login successful for user: \(user.name)")
                    authManager.login()
                    
                case .failure(let error):
                    errorMessage = "Login failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loginWithMockUser() {
        email = "john@example.com"
        password = "Test@123"
        login()
    }
}

struct MinimalTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.15))
            .foregroundColor(.white)
            .cornerRadius(25)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }
}
 
#Preview {
    LoginView()
}
