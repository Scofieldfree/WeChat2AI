import Foundation

public enum ChatAction: Int, CaseIterable, Codable {
    case summary, todos, links, raw, opportunities, knowledge, viewpoints, resources, compare, conclusions, requirements, custom

    public var title: String {
        switch self {
        case .summary: return "总结聊天"
        case .todos: return "提取待办"
        case .links: return "整理链接"
        case .raw: return "仅复制记录"
        case .opportunities: return "发现需求与产品机会"
        case .knowledge: return "提炼知识笔记"
        case .viewpoints: return "梳理观点与争议"
        case .resources: return "提取资源清单"
        case .compare: return "对比新增变化"
        case .conclusions: return "更新项目结论"
        case .requirements: return "整理产品需求"
        case .custom: return "自定义任务…"
        }
    }

    public var instruction: String {
        switch self {
        case .summary: return "请总结以下微信聊天：核心话题、结论、待确认事项。区分发言人的观点与事实，不要把营销表述当作已验证事实。"
        case .todos: return "请从以下聊天提取待办，列出事项、负责人、时间与原文依据。未明确的字段写「未明确」。"
        case .links: return "请整理以下聊天中的链接与提到的工具、服务；保留上下文，没有 URL 时不要编造。"
        case .raw: return ""
        case .opportunities: return "请从聊天中发现需求与产品机会，按目标用户、具体场景、痛点、现有解决方式、机会假设、验证问题整理。区分明确表达的需求与分析推测，不把单次发言当成普遍需求或已验证市场机会。每项附发言人与时间依据。"
        case .knowledge: return "请把聊天整理成可复习的知识笔记，包含主题、关键概念、方法步骤、案例、适用条件和注意事项。保留重要上下文，区分群友经验、个人观点与有依据的事实，不确定说法列为待核实。"
        case .viewpoints: return "请梳理讨论中的主要观点、支持者、论据、共识、分歧和未解决问题。区分事实争议、目标不同与方案取舍；没有回应不代表达成共识，不用多数人赞同代替事实核验。引用发言人与时间。"
        case .resources: return "请提取聊天里的工具、产品、开源项目、文章、课程及其他资源，整理名称、类别、用途、推荐或反对理由、适用场景、链接和发言依据。合并明确相同的资源，未提供的链接或价格写未明确，不补造资料。"
        case .compare: return "请将本批聊天与明确选定的历史批次比较，分别列出新增信息、重复内容、观点变化、矛盾与仍待确认的问题，引用双方批次、发言人与时间。导入先后不等于聊天先后，导出范围可能重叠；不能把本批所有内容都当作新消息。只比较任务清单列出的资料。"
        case .conclusions: return "请结合本批聊天及明确选择的历史批次、已有成果，提出项目结论更新稿：列出保留、新增、修订、撤回的结论及证据，整理待验证问题与下一步行动。若未选已有成果，先形成初稿，不声称已经与旧结论比较。仅在回复中给出更新建议；需要写入或覆盖项目文件时，先由我确认。"
        case .requirements: return "请把群聊中关于产品如何做的讨论整理成产品需求草案。按背景与目标、目标用户与使用场景、需求条目、交互流程、业务规则、异常与边界、验收条件、待确认问题组织。每条需求给出编号和原文依据，明确标注已明确同意、个人建议、存在分歧或分析推导；没有明确决定就不要标为已确认。优先级、负责人、排期、指标和验收细节未提及的写未明确，你补充的建议单独标注。保留取舍与不做的范围，不把零散讨论伪造成已经批准的完整 PRD。"
        case .custom: return "请按用户填写的自定义分析要求处理本批资料。"
        }
    }
}

/// Desktop handoff only: opens a workspace and prefills the composer.
/// This URL contains a short instruction, never the transcript or an auto-send flag.
public enum CodexHandoff {
    public static func makeURL(workspace: URL, action: ChatAction, project: URL? = nil) throws -> URL {
        let workingDirectory = try AgentPrompt.validate(workspace: workspace, project: project)
        let root = workspace.standardizedFileURL
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [URLQueryItem(name: "path", value: workingDirectory.path),
                                 URLQueryItem(name: "prompt", value: AgentPrompt.make(workspace: root, for: action, project: project)),
                                 URLQueryItem(name: "mode", value: "codex")]
        // The desktop uses JavaScript URLSearchParams (form decoding), where + means a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw CoreError.invalid("无法创建 Codex 打开链接。") }
        return url
    }
}
