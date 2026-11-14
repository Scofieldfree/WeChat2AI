import Foundation

extension WeChat2AICoreTests {
    func testCodexURLPreservesSpecialPathAndOnlyPrefills() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("聊天 & + # ? % " + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try "PRIVATE_TRANSCRIPT_NOT_IN_URL".write(to: workspace.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: workspace.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let url = try CodexHandoff.makeURL(workspace: workspace, action: .todos)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "threads")
        XCTAssertEqual(components.path, "/new")
        XCTAssertEqual(components.queryItems?.map(\.name), ["path", "prompt", "mode"])
        XCTAssertEqual(components.queryItems?.first?.value, workspace.standardizedFileURL.path)
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertFalse(components.percentEncodedQuery!.contains("+"))
        XCTAssertTrue(components.queryItems![1].value!.contains("提取待办"))
        XCTAssertFalse(url.absoluteString.contains("PRIVATE_TRANSCRIPT_NOT_IN_URL"))
        XCTAssertEqual(components.queryItems?.last?.value, "codex")
        XCTAssertTrue(components.queryItems![1].value!.contains(workspace.standardizedFileURL.path))
        XCTAssertTrue(components.queryItems![1].value!.contains(workspace.standardizedFileURL.appendingPathComponent("transcript.md").path))
        XCTAssertNil(components.fragment)
    }

    func testCodexMissingWorkspaceFails() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try CodexHandoff.makeURL(workspace: missing, action: .summary))
        XCTAssertThrowsError(try CodexHandoff.makeURL(workspace: URL(string: "https://example.com")!, action: .summary))
    }

    func testCodexActionsUseWorkspaceAndPreserveRawIntent() {
        for action in ChatAction.allCases {
            let prompt = AgentPrompt.make(workspace: URL(fileURLWithPath: "/tmp/WeChat2AI-Synthetic/聊天目录"), for: action)
            XCTAssertTrue(prompt.contains("transcript.md"))
            XCTAssertTrue(prompt.contains("manifest.json"))
            XCTAssertTrue(prompt.contains("messages.jsonl"))
            XCTAssertTrue(prompt.contains("original/"))
            if action == .raw {
                XCTAssertTrue(prompt.contains("等待我补充具体分析要求"))
            } else {
                XCTAssertTrue(prompt.contains(action.instruction))
            }
        }
        XCTAssertEqual(ChatAction.raw.instruction, "")
    }
}
