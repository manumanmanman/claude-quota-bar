import SwiftUI
import AppKit
import Security
import ServiceManagement

// MARK: - App Entry Point

@main
struct ClaudeQuotaBarApp: App {
    @StateObject private var usageService = UsageService()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(service: usageService)
        } label: {
            MenuBarLabel(service: usageService)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label (rendered as NSImage)

struct MenuBarLabel: View {
    @ObservedObject var service: UsageService

    var body: some View {
        Image(nsImage: renderMenuBarImage())
    }

    private func renderMenuBarImage() -> NSImage {
        let pct = service.fiveHourPct
        let reset = service.resetText

        let barWidth: CGFloat = 72
        let barHeight: CGFloat = 4
        let barY: CGFloat = 7
        let height: CGFloat = 18
        let spacing: CGFloat = 4

        let nsAccent = nsAccentColor(for: pct)
        let nsSecondary = NSColor.secondaryLabelColor

        let pctStr = pct.map { "\(Int($0))%" } ?? "—"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: nsAccent,
        ]
        let pctSize = (pctStr as NSString).size(withAttributes: pctAttrs)

        var totalWidth: CGFloat = barWidth + spacing + pctSize.width

        var resetStr: String?
        var resetSize: CGSize = .zero
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: nsSecondary,
        ]
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: nsSecondary,
        ]
        let dotSize = ("·" as NSString).size(withAttributes: dotAttrs)

        if let r = reset {
            resetStr = r
            resetSize = (r as NSString).size(withAttributes: resetAttrs)
            totalWidth += spacing + dotSize.width + spacing + resetSize.width
        }

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            var x: CGFloat = 0

            // Progress bar track
            let trackRect = NSRect(x: x, y: barY, width: barWidth, height: barHeight)
            let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2)
            NSColor.white.withAlphaComponent(0.25).setFill()
            trackPath.fill()

            // Progress bar fill
            if let pct {
                let fillWidth = max(1, barWidth * pct / 100)
                let fillRect = NSRect(x: x, y: barY, width: fillWidth, height: barHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
                nsAccent.setFill()
                fillPath.fill()
            }
            x += barWidth + spacing

            // Percentage text
            let pctY = (height - pctSize.height) / 2
            (pctStr as NSString).draw(at: NSPoint(x: x, y: pctY), withAttributes: pctAttrs)
            x += pctSize.width

            // Reset time
            if let resetStr {
                x += spacing
                let dotY = (height - dotSize.height) / 2
                ("·" as NSString).draw(at: NSPoint(x: x, y: dotY), withAttributes: dotAttrs)
                x += dotSize.width + spacing
                let resetY = (height - resetSize.height) / 2
                (resetStr as NSString).draw(at: NSPoint(x: x, y: resetY), withAttributes: resetAttrs)
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func nsAccentColor(for pct: Double?) -> NSColor {
        guard let pct else { return .secondaryLabelColor }
        if pct >= 80 { return .systemRed }
        if pct >= 50 { return .systemOrange }
        return .systemBlue
    }
}

// MARK: - Dropdown Window

struct DropdownView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code Usage")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            UsageRow(label: "Fenêtre 5h", pct: service.fiveHourPct)
            UsageRow(label: "Fenêtre 7 jours", pct: service.sevenDayPct)

            Divider()

            if let resetText = service.resetText {
                HStack {
                    Text("Reset dans")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(resetText)
                        .fontWeight(.medium)
                }
                .font(.system(size: 12))
            }

            if let error = service.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Button("Rafraîchir") {
                    Task { await service.fetch() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

struct UsageRow: View {
    let label: String
    let pct: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                Spacer()
                Text(pct.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(height: 4)
                    if let pct {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor)
                            .frame(width: max(1, geo.size.width * pct / 100), height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
    }

    private var accentColor: Color {
        guard let pct else { return .blue }
        if pct >= 80 { return .red }
        if pct >= 50 { return .orange }
        return .blue
    }
}

// MARK: - Usage Service

@MainActor
final class UsageService: ObservableObject {
    @Published var fiveHourPct: Double?
    @Published var sevenDayPct: Double?
    @Published var resetsAt: Date?
    @Published var lastError: String?

    private var timer: Timer?
    private static let refreshInterval: TimeInterval = 240 // 4 minutes

    var resetText: String? {
        guard let resetsAt else { return nil }
        let diff = resetsAt.timeIntervalSinceNow
        guard diff > 0 else { return nil }
        let totalMinutes = Int(diff) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return m > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(h)h"
        }
        return "\(m)m"
    }

    private static let retryInterval: TimeInterval = 30

    init() {
        Task { await fetch() }
        startTimer(interval: Self.refreshInterval)
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetch()
            }
        }
    }

    func fetch() async {
        do {
            let token = try KeychainHelper.readOAuthToken()
            let usage = try await APIClient.fetchUsage(token: token)
            fiveHourPct = usage.fiveHour.utilization
            sevenDayPct = usage.sevenDay.utilization
            if let resetStr = usage.fiveHour.resetsAt {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetsAt = fmt.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
            }
            lastError = nil
            startTimer(interval: Self.refreshInterval)
        } catch {
            lastError = error.localizedDescription
            startTimer(interval: Self.retryInterval)
        }
    }
}

// MARK: - Keychain Helper

enum KeychainError: LocalizedError {
    case notFound
    case unexpectedData
    case noOAuthToken

    var errorDescription: String? {
        switch self {
        case .notFound: return "Claude Code credentials not found in Keychain"
        case .unexpectedData: return "Could not parse Keychain data"
        case .noOAuthToken: return "No OAuth token in credentials"
        }
    }
}

enum KeychainHelper {
    static func readOAuthToken() throws -> String {
        let username = NSUserName()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError.notFound }
        guard let data = result as? Data else { throw KeychainError.unexpectedData }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let oauth = json?["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw KeychainError.noOAuthToken
        }
        return token
    }
}

// MARK: - API Client

struct UsageResponse: Codable {
    let fiveHour: Window
    let sevenDay: Window

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    struct Window: Codable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

enum APIError: LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "API error: HTTP \(code)"
        }
    }
}

enum APIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}
