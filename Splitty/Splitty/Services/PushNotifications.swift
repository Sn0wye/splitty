//
//  PushNotifications.swift
//  Splitty
//

import SwiftUI
import UserNotifications

/// Everything push on this device: the permission, the APNs token, and the group a tapped
/// notification opens. The server decides what is sent and to whom; see "Push
/// notifications" in CONTEXT.md.
@MainActor
final class PushNotifications: ObservableObject {
    static let shared = PushNotifications()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// The group a tapped notification asked for, until the signed-in app opens it.
    @Published var groupToOpen: Int?

    /// Read when a notification arrives in the foreground, to tell whether its group is
    /// already on screen.
    weak var appState: AppState?

    private var deviceToken: String?
    private let center = UNUserNotificationCenter.current()
    private static let offeredKey = "notifications.offered"

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// On launch and sign-in. Asks for nothing: it only registers when the user already said
    /// yes, since the token can change between launches.
    func registerIfAllowed() async {
        await refreshAuthorization()
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// The system prompt. Called from the in-app offer and from Settings, never on launch.
    func requestPermission() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Called when notifications start being worth something: joining a group, creating an
    /// invite, saving an expense others share. Asks once, in the app's own words, before
    /// the system prompt. A "Not Now" is final; Settings still has the switch.
    func offerIfUseful() {
        guard !UserDefaults.standard.bool(forKey: Self.offeredKey),
              !PerformanceScenarioLaunch.isEnabled else { return }

        Task {
            await refreshAuthorization()
            guard authorization == .notDetermined else { return }
            // Lets the sheet that triggered this finish dismissing first.
            try? await Task.sleep(for: .milliseconds(700))
            presentOffer()
        }
    }

    /// UIKit rather than a SwiftUI alert, so it shows over whatever sheet is up.
    private func presentOffer() {
        guard let presenter = Self.topViewController else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)

        let alert = UIAlertController(
            title: L10n.Notifications.offerTitle,
            message: L10n.Notifications.offerMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Notifications.offerDecline, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Notifications.offerAccept, style: .default) { _ in
            Task { await PushNotifications.shared.requestPermission() }
        })
        presenter.present(alert, animated: true)
    }

    func didRegister(deviceToken token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    /// Sends the token with the app's language. Again after a language change, since the
    /// server writes the text.
    func upload() async {
        guard let deviceToken, AuthenticationManager.shared.isAuthenticated else { return }
        do {
            try await NotificationService.shared.registerDevice(token: deviceToken, language: LanguageManager.shared.language)
        } catch {
            print("⚠️ Could not register for push notifications: \(error.localizedDescription)")
        }
    }

    /// A notification about the group already on screen refreshes it instead of showing a
    /// banner over it.
    func presentation(for userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
        guard let groupId = Self.groupId(in: userInfo),
              let appState,
              appState.selectedTab == .groups,
              appState.groupsPath.last == groupId else {
            return [.banner, .list, .sound]
        }
        Task { await appState.groupSessions.session(for: groupId)?.refresh() }
        return []
    }

    func open(_ userInfo: [AnyHashable: Any]) {
        groupToOpen = Self.groupId(in: userInfo)
    }

    nonisolated static func groupId(in userInfo: [AnyHashable: Any]) -> Int? {
        (userInfo["groupId"] as? Int) ?? (userInfo["groupId"] as? NSNumber)?.intValue
    }

    private static var topViewController: UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// The app delegate exists for the two things SwiftUI has no hook for: the APNs token and
/// the notification center's delegate.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushNotifications.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ APNs registration failed: \(error.localizedDescription)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        return await MainActor.run { PushNotifications.shared.presentation(for: userInfo) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { PushNotifications.shared.open(userInfo) }
    }
}
