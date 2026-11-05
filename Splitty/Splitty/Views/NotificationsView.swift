//
//  NotificationsView.swift
//  Splitty
//

import SwiftUI

/// Where the notification switches come from. The review gallery passes one held in memory.
@MainActor
struct NotificationSettingsDataSource {
    var load: () async throws -> NotificationSettings
    var save: (NotificationSettings) async throws -> NotificationSettings

    static let live = NotificationSettingsDataSource(
        load: { try await NotificationService.shared.settings() },
        save: { try await NotificationService.shared.save($0) }
    )
}

/// Settings > Notifications: the main switch, then one switch per kind. The system
/// permission sits on top, because without it no switch here does anything.
struct NotificationsView: View {
    var dataSource: NotificationSettingsDataSource = .live

    @ObservedObject private var push = PushNotifications.shared
    @Environment(\.openURL) private var openURL
    @State private var settings: NotificationSettings?
    @State private var loadError: String?
    @State private var saveError: String?

    var body: some View {
        List {
            permissionSection

            if let settings {
                SwiftUI.Group {
                    Section {
                        Toggle(L10n.Notifications.receive, isOn: binding(\.enabled, in: settings))
                            .frame(minHeight: 44)
                    }

                    ForEach(NotificationKind.Section.allCases) { section in
                        Section {
                            ForEach(section.kinds) { kind in
                                kindToggle(kind, in: settings)
                            }
                        } header: {
                            Text(section.title)
                        }
                        .disabled(!settings.enabled)
                    }
                }
                // Without the permission no switch here does anything.
                .disabled(push.authorization == .denied)
            } else if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button(L10n.Common.tryAgain) { Task { await load() } }
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("background").ignoresSafeArea())
        .navigationTitle(Text(L10n.Notifications.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await push.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Back from the Settings app, where the permission may have changed.
            Task { await push.refreshAuthorization() }
        }
        .alert(
            Text(L10n.Notifications.saveFailed),
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button(L10n.Common.ok, role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch push.authorization {
        case .denied:
            Section {
                Text(L10n.Notifications.systemOff)
                    .foregroundStyle(Color("muted-foreground"))
                Button(L10n.Notifications.openSettings) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .frame(minHeight: 44)
            }
        case .notDetermined:
            Section {
                Button(L10n.Notifications.turnOn) {
                    Task { await push.requestPermission() }
                }
                .frame(minHeight: 44)
            }
        default:
            EmptyView()
        }
    }

    private func kindToggle(_ kind: NotificationKind, in settings: NotificationSettings) -> some View {
        Toggle(isOn: Binding(
            get: { settings.isOn(kind) },
            set: { save(settings.setting(kind, on: $0)) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(Color("muted-foreground"))
            }
        }
        .frame(minHeight: 44)
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>, in settings: NotificationSettings) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var changed = settings
                changed[keyPath: keyPath] = value
                save(changed)
            }
        )
    }

    private func load() async {
        loadError = nil
        do {
            settings = try await dataSource.load()
        } catch {
            if !error.isCancellation { loadError = error.displayMessage }
        }
    }

    /// Shows the change at once and puts it back if the server refuses it.
    private func save(_ changed: NotificationSettings) {
        let previous = settings
        settings = changed
        Task {
            do {
                settings = try await dataSource.save(changed)
            } catch {
                settings = previous
                saveError = error.displayMessage
            }
        }
    }
}

extension NotificationKind {
    var title: String {
        switch self {
        case .expenseAdded: L10n.Notifications.expenseAdded
        case .recurringExpenseAdded: L10n.Notifications.recurringExpenseAdded
        case .expenseChanged: L10n.Notifications.expenseChanged
        case .expenseDeleted: L10n.Notifications.expenseDeleted
        case .paymentReceived: L10n.Notifications.paymentReceived
        case .paymentChanged: L10n.Notifications.paymentChanged
        case .paymentDeleted: L10n.Notifications.paymentDeleted
        case .paymentReminder: L10n.Notifications.paymentReminder
        case .inviteAccepted: L10n.Notifications.inviteAccepted
        case .removedFromGroup: L10n.Notifications.removedFromGroup
        }
    }

    var detail: String {
        switch self {
        case .expenseAdded: L10n.Notifications.expenseAddedDetail
        case .recurringExpenseAdded: L10n.Notifications.recurringExpenseAddedDetail
        case .expenseChanged: L10n.Notifications.expenseChangedDetail
        case .expenseDeleted: L10n.Notifications.expenseDeletedDetail
        case .paymentReceived: L10n.Notifications.paymentReceivedDetail
        case .paymentChanged: L10n.Notifications.paymentChangedDetail
        case .paymentDeleted: L10n.Notifications.paymentDeletedDetail
        case .paymentReminder: L10n.Notifications.paymentReminderDetail
        case .inviteAccepted: L10n.Notifications.inviteAcceptedDetail
        case .removedFromGroup: L10n.Notifications.removedFromGroupDetail
        }
    }
}

extension NotificationKind.Section {
    var title: String {
        switch self {
        case .expenses: L10n.Notifications.sectionExpenses
        case .payments: L10n.Notifications.sectionPayments
        case .reminders: L10n.Notifications.sectionReminders
        case .group: L10n.Notifications.sectionGroup
        }
    }
}

#Preview {
    NavigationStack {
        NotificationsView(dataSource: NotificationSettingsDataSource(
            load: { NotificationSettings(enabled: true, muted: [.expenseChanged]) },
            save: { $0 }
        ))
    }
}
