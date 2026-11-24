// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit

/// The visual vocabulary of Research Explorer.
///
/// Liquid Glass belongs to native navigation, toolbar and primary interaction
/// controls. Reading and evidence surfaces deliberately remain opaque, which
/// keeps long-form text legible in light/dark and Reduce Transparency modes.
enum ExplorerDesign {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 10
        static let card: CGFloat = 18
        static let large: CGFloat = 24
    }

    enum Layout {
        static let articleMaxWidth: CGFloat = 740
        static let contentMaxWidth: CGFloat = 1100
        static let sidebarIdealWidth: CGFloat = 242
        static let outlineWidth: CGFloat = 238
        static let evidenceWidth: CGFloat = 328
        static let outlineBreakpoint: CGFloat = 760
        static let evidenceBreakpoint: CGFloat = 1100
        static let compactEvidenceWidth: CGFloat = 360
    }

    enum Palette {
        // Dynamic AppKit system colors preserve contrast and appearance changes.
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let paper = Color(nsColor: .textBackgroundColor)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let subtle = Color(nsColor: .underPageBackgroundColor)
        static let ink = Color.primary
        static let secondaryInk = Color.secondary
        static let accent = Color.accentColor
        static let hairline = Color.primary.opacity(0.11)
        static let accentWash = Color.accentColor.opacity(0.09)
        static let cautionWash = Color.orange.opacity(0.09)
    }

    /// State-driven motion vocabulary shared by the native dashboard.
    ///
    /// Durations are intentionally short enough to settle between the existing
    /// 250 ms observation updates. These are presentation transitions only:
    /// they never schedule work, defer cancellation, or imply network traffic.
    enum Motion {
        /// Distinguishes data changes from explicit selection and status feedback.
        enum Role: CaseIterable {
            case metric, chart, selection, status

            /// Nominal animation duration in seconds (spring settling can differ).
            var duration: TimeInterval {
                switch self {
                case .metric: 0.18
                case .chart: 0.16
                case .selection: 0.20
                case .status: 0.22
                }
            }
        }

        /// Resolves the native animation for a role, or nil when Reduce Motion is enabled.
        /// - Parameters:
        ///   - role: The kind of visual change, never a business operation.
        ///   - reduceMotion: SwiftUI's system accessibility preference.
        /// - Returns: A short animation or no animation.
        static func animation(_ role: Role, reduceMotion: Bool) -> Animation? {
            guard !reduceMotion else { return nil }
            switch role {
            case .metric, .chart: return .easeOut(duration: role.duration)
            case .selection: return .snappy(duration: role.duration, extraBounce: 0)
            case .status: return .smooth(duration: role.duration, extraBounce: 0)
            }
        }
    }

    enum Reader {
        static let minimumSize = 14.0
        static let maximumSize = 26.0
        static let defaultSize = 17.0
    }

    enum Typography {
        static let display: Font = .system(size: 36, weight: .semibold, design: .serif)
        static let pageTitle: Font = .system(size: 32, weight: .semibold, design: .serif)
        static let section: Font = .system(size: 22, weight: .semibold, design: .serif)
        static let panel: Font = .system(size: 16, weight: .semibold)
        static let eyebrow: Font = .system(size: 11, weight: .semibold)
        static let body: Font = .system(size: 14)
        static let detail: Font = .system(size: 12)
        static let mono: Font = .system(size: 12, weight: .regular, design: .monospaced)

        static func article(size: Double) -> Font {
            .system(size: CGFloat(min(Reader.maximumSize, max(Reader.minimumSize, size))), weight: .regular, design: .serif)
        }
    }
}

/// A content-layer paper panel; intentionally *not* Liquid Glass.
/// The system owns glass effects on window chrome, sidebars and controls.
struct ExplorerPanel<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(ExplorerDesign.Space.lg)
            .background(
                ExplorerDesign.Palette.paper,
                in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExplorerDesign.Radius.card, style: .continuous)
                    .strokeBorder(ExplorerDesign.Palette.hairline, lineWidth: 1)
            }
    }
}

struct ExplorerScreenHeading: View {
    let eyebrow: String
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            Text(eyebrow.uppercased())
                .font(ExplorerDesign.Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(ExplorerDesign.Palette.accent)
            Text(title)
                .font(ExplorerDesign.Typography.display)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .font(ExplorerDesign.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ExplorerPillTone {
    case neutral, accent, caution

    var foreground: Color {
        switch self {
        case .neutral: .secondary
        case .accent: ExplorerDesign.Palette.accent
        case .caution: .orange
        }
    }

    var background: Color {
        switch self {
        case .neutral: ExplorerDesign.Palette.control
        case .accent: ExplorerDesign.Palette.accentWash
        case .caution: ExplorerDesign.Palette.cautionWash
        }
    }
}

/// A compact, semantic status indicator with state-driven text replacement.
struct ExplorerPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let symbol: String
    var tone: ExplorerPillTone = .neutral

    var body: some View {
        Label(title, systemImage: symbol)
            .font(ExplorerDesign.Typography.detail)
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(ExplorerDesign.Motion.animation(.status, reduceMotion: reduceMotion), value: title)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, ExplorerDesign.Space.sm)
            .padding(.vertical, ExplorerDesign.Space.xs)
            .background(tone.background, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

/// A measured KPI tile. Numeric transitions are cosmetic; the string remains
/// the exact observed value. Unavailable and missing samples never count as zero.
struct ExplorerMetricTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                Label(title, systemImage: symbol)
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                metricText
                    .font(value == "Unavailable" || value == "No samples"
                          ? .system(size: 16, weight: .semibold)
                          : .system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var metricText: some View {
        if let numeric = value.split(separator: " ").first.flatMap({ Double($0) }), numeric.isFinite {
            Text(value)
                .contentTransition(reduceMotion ? .identity : .numericText(value: numeric))
                .animation(ExplorerDesign.Motion.animation(.metric, reduceMotion: reduceMotion), value: value)
        } else {
            Text(value)
        }
    }
}
