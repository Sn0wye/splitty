import SwiftUI

/// Says how what is on screen stands with the server: offline, read a while ago, or holding
/// writes not sent yet. Shows nothing when everything is current. Tapping it, when there are
/// unsent writes, opens the list of them.
struct SyncStatusBanner: View {
    let isOffline: Bool
    let savedAt: Date?
    var waitingCount = 0
    var attentionCount = 0
    var onOpen: (() -> Void)? = nil

    var body: some View {
        if let line = primaryLine {
            Button {
                onOpen?()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: line.symbol)
                        .foregroundStyle(line.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color("foreground"))
                        if let detail = secondaryLine {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(Color("muted-foreground"))
                        }
                    }
                    Spacer(minLength: 0)
                    if onOpen != nil, waitingCount + attentionCount > 0 {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color("muted-foreground"))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color("muted"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil || waitingCount + attentionCount == 0)
            .accessibilityElement(children: .combine)
        }
    }

    private struct Line {
        let text: String
        let symbol: String
        let tint: Color
    }

    /// The most pressing thing first: a write that needs the member, then being offline,
    /// then writes waiting, then an old copy.
    private var primaryLine: Line? {
        if attentionCount > 0 {
            return Line(text: L10n.Sync.needsAttention(attentionCount), symbol: "exclamationmark.circle.fill", tint: Color("negative"))
        }
        if isOffline {
            return Line(text: L10n.Sync.offline, symbol: "wifi.slash", tint: Color("muted-foreground"))
        }
        if waitingCount > 0 {
            return Line(text: L10n.Sync.waiting(waitingCount), symbol: "clock", tint: Color("muted-foreground"))
        }
        if savedAt != nil {
            return Line(text: L10n.Sync.couldNotRefresh, symbol: "arrow.clockwise", tint: Color("muted-foreground"))
        }
        return nil
    }

    private var secondaryLine: String? {
        var parts: [String] = []
        if attentionCount > 0 || isOffline, waitingCount > 0 { parts.append(L10n.Sync.waiting(waitingCount)) }
        if let savedAt { parts.append(L10n.Sync.lastUpdated(Self.relative(savedAt))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// The small mark beside a row's title while this device holds a write for it.
struct RowSyncBadge: View {
    let state: RowSyncState

    var body: some View {
        switch state {
        case .waiting:
            Image(systemName: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("muted-foreground"))
                .accessibilityLabel(L10n.Sync.rowWaiting)
        case .needsAttention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("negative"))
                .accessibilityLabel(L10n.Sync.rowNeedsAttention)
        }
    }
}
