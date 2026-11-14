import SwiftUI

struct W2AButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        W2AButtonBody(configuration: configuration, primary: primary, compact: compact)
    }
}

private struct W2AButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    private var background: Color {
        if primary { return Color(nsColor: configuration.isPressed ? W2ATheme.Colors.primaryActive : hovered ? W2ATheme.Colors.primaryHover : W2ATheme.Colors.primary) }
        return configuration.isPressed || hovered ? Color(nsColor: W2ATheme.Colors.hover) : .w2aElevated
    }
    var body: some View {
        configuration.label.font(W2ATheme.TypeStyle.section)
            .padding(.horizontal, W2ATheme.Space.md).frame(minHeight: primary ? 32 : compact ? 28 : 31)
            .foregroundStyle(primary ? Color(nsColor: W2ATheme.Colors.onPrimary) : .w2aText)
            .background(background, in: RoundedRectangle(cornerRadius: W2ATheme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: W2ATheme.Radius.control).strokeBorder(primary ? .clear : Color(nsColor: contrast == .increased ? W2ATheme.Colors.secondaryText : W2ATheme.Colors.borderStrong), lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .overlay { if focused { RoundedRectangle(cornerRadius: W2ATheme.Radius.control + 2).stroke(Color.w2aAccent, lineWidth: 2).padding(-4) } }
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : W2ATheme.Motion.control, value: hovered)
    }
}

struct W2ADivider: View {
    var vertical = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(Color(nsColor: contrast == .increased ? W2ATheme.Colors.secondaryText : W2ATheme.Colors.border))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1).accessibilityHidden(true)
    }
}

struct W2AStatus: View {
    let message: String
    var tone: AppModel.StatusTone = .neutral
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: W2ATheme.Space.sm) {
            if tone == .working { ProgressView().controlSize(.small).accessibilityLabel("正在处理") }
            else { Image(systemName: tone.symbol).foregroundStyle(color).accessibilityHidden(true) }
            Text(message).foregroundStyle(Color.w2aSecondary)
                .lineLimit(compact ? 1 : nil).textSelection(.enabled)
        }.font(W2ATheme.TypeStyle.section).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var color: Color {
        switch tone {
        case .success: return Color(nsColor: W2ATheme.Colors.success)
        case .warning: return Color(nsColor: W2ATheme.Colors.warning)
        case .error: return Color(nsColor: W2ATheme.Colors.error)
        default: return .w2aSecondary
        }
    }
}

struct W2AEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: W2ATheme.Space.lg) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Color.w2aSecondary).accessibilityHidden(true)
            Text(title).font(W2ATheme.TypeStyle.emptyTitle)
            Text(message).font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aSecondary)
                .multilineTextAlignment(.center).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            actions()
        }.padding(W2ATheme.Space.panel).frame(maxWidth: 440).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct W2ASheetLayout<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: W2ATheme.Space.sm) {
                Text(title).font(W2ATheme.TypeStyle.emptyTitle).fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty { Text(subtitle).foregroundStyle(Color.w2aSecondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(W2ATheme.Space.panel)
            W2ADivider()
            ScrollView {
                VStack(alignment: .leading, spacing: W2ATheme.Space.md, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(W2ATheme.Space.panel)
            }.frame(maxHeight: .infinity)
            W2ADivider()
            HStack(spacing: W2ATheme.Space.sm, content: actions).padding(W2ATheme.Space.lg)
        }.font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aText)
            .background(Color.w2aElevated).tint(Color.w2aAccent).accentColor(Color.w2aAccent).buttonStyle(W2AButtonStyle())
    }
}

struct W2ALinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aSecondary)
            .padding(.horizontal, 4).frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
            .background(configuration.isPressed ? Color(nsColor: W2ATheme.Colors.hover) : .clear)
    }
}
