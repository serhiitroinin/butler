import ButlerCore
import SwiftUI

/// The flat label next to the folder name.
struct StatusLabel: View {
    let status: ProposalStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(status == .proposed || status == .undone ? 0.10 : 0.16)))
            .accessibilityLabel("Status: \(status.rawValue)")
    }

    private var tone: Color {
        switch status {
        case .proposed, .undone: return Stock.ink.opacity(0.75)
        case .working: return Stock.slate
        case .approved: return Stock.accent
        case .rejected: return Stock.red
        }
    }
}

/// A small flat capsule at the right edge of a row: `Excluded`.
struct FlatCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Stock.ink.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Stock.ink.opacity(0.09)))
    }
}

/// A quiet flat checkbox in the accent, with a mixed state for groups.
struct InkCheckbox: View {
    let state: InclusionState
    let label: String
    let toggle: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            toggle(state == .excluded)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(state == .excluded ? Color.clear : Stock.accent)
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(state == .excluded ? Stock.ink.opacity(0.32) : Color.clear, lineWidth: 1)
                if state == .included {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Stock.onAccent)
                } else if state == .mixed {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Stock.onAccent)
                        .frame(width: 7, height: 1.6)
                }
            }
            .frame(width: 13, height: 13)
            .opacity(isEnabled ? 1 : 0.55)
            .frame(width: Layout.checkColumn, height: Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityValue(state == .included ? "included" : state == .mixed ? "partly included" : "excluded")
    }
}

/// What was asked and what came back, flat, above the bottom bar.
struct ConversationBlock: View {
    let turns: [ConversationTurn]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(turns.suffix(2)) { turn in
                line("You:", turn.request, emphasis: false)
                line("Butler:", turn.reply ?? "Working…", emphasis: turn.reply == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, 9)
    }

    private func line(_ who: String, _ text: String, emphasis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(who)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Stock.ink)
                .frame(width: 44, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(emphasis ? Stock.tertiary : Stock.ink.opacity(0.8))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

/// A thin olive line: determinate while applying, sweeping while the engine works.
struct ProgressLine: View {
    var fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Stock.ink.opacity(0.10))
                if let fraction {
                    Capsule()
                        .fill(Stock.accent)
                        .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
                        .animation(.easeInOut(duration: 0.2), value: fraction)
                } else if reduceMotion {
                    Capsule().fill(Stock.accent.opacity(sweep ? 0.9 : 0.35))
                } else {
                    Capsule()
                        .fill(Stock.accent)
                        .frame(width: proxy.size.width * 0.3)
                        .offset(x: sweep ? proxy.size.width * 0.7 : 0)
                }
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            guard fraction == nil else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

/// The quiet button: a hairline outline and ink, never a fill, so the one
/// olive button beside it stays the primary action in both appearances. The
/// stock bordered style fills brighter than the olive in dark.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Stock.ink.opacity(isEnabled ? 0.85 : 0.35))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5.5).fill(configuration.isPressed ? Stock.wash : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 5.5).strokeBorder(Stock.ink.opacity(isEnabled ? 0.22 : 0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 5.5))
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}
