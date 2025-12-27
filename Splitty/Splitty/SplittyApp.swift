//
//  SplittyApp.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

@main
struct SplittyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isCheckingAuth = true
    
    var body: some View {
        ZStack {
            if isCheckingAuth {
                SplashView()
            } else if authManager.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            checkAuthenticationStatus()
        }
    }
    
    private func checkAuthenticationStatus() {
        // Add a small delay to show the splash screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            authManager.checkAuthenticationStatus()
            isCheckingAuth = false
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Splitty")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ProgressView()
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
