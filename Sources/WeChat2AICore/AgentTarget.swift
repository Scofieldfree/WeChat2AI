import Foundation

public enum AgentTarget: String, CaseIterable {
    case codex, claudeCode, claudeCowork

    // Each destination is selected and restored independently.
    public static let pickerTargets: [AgentTarget] = [.codex, .claudeCode, .claudeCowork]
    public static let preferenceKey = "selectedDesktopAgent"
    public static func restored(_ value: String?) -> AgentTarget {
        value.flatMap(Self.init(rawValue:)) ?? .codex
    }
    public var title: String {
        switch self { case .codex: return "Codex"; case .claudeCode: return "Claude Code"; case .claudeCowork: return "Claude Cowork" }
    }
    public var bundleIdentifier: String { self == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop" }
    public func makeURL(workspace: URL, action: ChatAction, project: URL?) throws -> URL {
        switch self {
        case .codex: return try CodexHandoff.makeURL(workspace: workspace, action: action, project: project)
        case .claudeCode: return try ClaudeCodeHandoff.makeURL(workspace: workspace, action: action, project: project)
        case .claudeCowork: return try ClaudeCoworkHandoff.makeURL(workspace: workspace, action: action, project: project)
        }
    }
}

public enum TaskDelivery: Equatable {
    case copy
    case desktop(AgentTarget)
    public var agent: AgentTarget? { if case .desktop(let target) = self { return target }; return nil }
}

/// Resolve the application before creating any snapshot. Opening is handled by AppKit.
public struct DesktopLaunch {
    public let application: URL
    public let handoff: HandoffResult
    public let url: URL

    public static func prepare(target: AgentTarget, application: URL?, action: ChatAction,
                               createHandoff: () throws -> HandoffResult) throws -> DesktopLaunch {
        guard let application else { throw CoreError.invalid("未找到 \(target.title) 桌面端，可使用「复制给 AI」。") }
        let handoff = try createHandoff()
        do {
            return DesktopLaunch(application: application, handoff: handoff,
                url: try target.makeURL(workspace: handoff.workspace, action: action, project: handoff.project))
        } catch {
            // This is a complete snapshot. Preserve it for manual access/retry.
            throw CoreError.invalid("未能准备 \(target.title) 打开链接：\(error.localizedDescription)\n资料副本已保留：\(handoff.workspace.path)；可使用「复制给 AI」。")
        }
    }
}
