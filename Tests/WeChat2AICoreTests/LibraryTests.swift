import Foundation
import Darwin

private func libraryFixture(_ body: (URL, LibraryStore, URL) throws -> Void) throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("WeChat2AI-library-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temp) }
    let sample = temp.appendingPathComponent("样本 + # & ?")
    try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: false)
    try "·Alice\n2026-9-19 10:37\n[Photo] demo.jpg\n\n·Bob\n2026-9-19 10:38:12\n这是一份虚构的测试记录".write(to: sample.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
    try Data([1, 4, 9, 16]).write(to: sample.appendingPathComponent("demo.jpg"))
    let store = try LibraryStore.create(at: temp.appendingPathComponent("资料库 + & # ?"))
    try body(temp, store, sample)
}

extension WeChat2AICoreTests {
    func testLibraryGroupingAndNames() throws {
        try libraryFixture { _, store, sample in
            let a = try store.createSource(name: "A群", note: "项目一"), b = try store.createSource(name: "A群", note: "项目二", kind: "direct")
            XCTAssertFalse(a.id == b.id); XCTAssertFalse(a.directoryName == b.directoryName)
            let one = try store.importData(from: sample), two = try store.importData(from: sample), three = try store.importData(from: sample)
            XCTAssertNil(one.source)
            try store.assign(batchID: one.id, to: a.id); try store.assign(batchID: two.id, to: a.id); try store.assign(batchID: three.id, to: b.id)
            let contents = try store.contents()
            XCTAssertEqual(contents.batches.filter { $0.source?.id == a.id }.count, 2)
            XCTAssertEqual(contents.batches.filter { $0.source?.id == b.id }.count, 1)
            let before = contents.batches.first { $0.id == one.id }!.workspace
            try store.renameSource(id: a.id, name: "A 群改名", note: "新备注")
            XCTAssertEqual(try store.contents().batches.first { $0.id == one.id }!.workspace, before)
            let maliciousName = try store.createSource(name: "../斜杠/群:名\\", note: "只是名称")
            XCTAssertFalse(maliciousName.directoryName.contains("/"))
            XCTAssertFalse(maliciousName.directoryName.hasPrefix("."))
            XCTAssertThrowsError(try store.createSource(name: " \n"))
        }
    }
    func testArchivePreservesFilesAndFailure() throws {
        try libraryFixture { _, store, sample in
            let batch = try store.importData(from: sample), a = try store.createSource(name: "A")
            let hashes = try LibraryIO.hashes(batch.workspace)
            XCTAssertThrowsError(try store.assign(batchID: batch.id, to: "missing"))
            XCTAssertEqual(try LibraryIO.hashes(batch.workspace), hashes)
            let moved = try store.assign(batchID: batch.id, to: a.id)
            XCTAssertEqual(try LibraryIO.hashes(moved.workspace), hashes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: batch.workspace.path))
            let unfiled = try store.assign(batchID: batch.id, to: nil)
            XCTAssertEqual(try LibraryIO.hashes(unfiled.workspace), hashes)
            XCTAssertEqual(try store.contents().batches.count, 1)
        }
    }
    func testLibraryUnavailableAndUnknownVersion() throws {
        try libraryFixture { temp, store, _ in
            let ordinary = temp.appendingPathComponent("ordinary")
            try FileManager.default.createDirectory(at: ordinary, withIntermediateDirectories: false)
            XCTAssertThrowsError(try LibraryStore.create(at: ordinary))
            XCTAssertThrowsError(try LibraryStore.open(at: ordinary))
            var metadata = store.metadata; metadata.schemaVersion = 99
            try LibraryIO.write(metadata, store.root.appendingPathComponent("library.json"))
            XCTAssertThrowsError(try LibraryStore.open(at: store.root))
            XCTAssertThrowsError(try store.createSource(name: "Must not create"))
            XCTAssertEqual(try LibraryIO.read(LibraryMetadata.self, store.root.appendingPathComponent("library.json")).schemaVersion, 99)
            try FileManager.default.moveItem(at: store.root, to: temp.appendingPathComponent("offline"))
            XCTAssertThrowsError(try store.contents())
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.path))
        }
    }
    func testCorruptBatchIsReportedAndSymlinkRejected() throws {
        try libraryFixture { temp, store, sample in
            let good = try store.importData(from: sample), broken = try store.importData(from: sample)
            try "broken".write(to: broken.workspace.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            let symlink = store.root.appendingPathComponent("sources/linked")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: temp)
            let data = try store.contents()
            XCTAssertEqual(data.batches.count, 1); XCTAssertEqual(data.batches.first?.id, good.id)
            XCTAssertEqual(data.warnings.count, 2)
            try FileManager.default.createSymbolicLink(at: good.workspace.appendingPathComponent("original/escape"), withDestinationURL: temp)
            XCTAssertThrowsError(try store.createHandoff(batchID: good.id, at: temp.appendingPathComponent("Handoffs")))
            XCTAssertTrue(FileManager.default.fileExists(atPath: broken.workspace.path))
        }
    }
    func testLibraryWriterExclusion() throws {
        try libraryFixture { _, store, _ in
            try store.withLock {
                XCTAssertThrowsError(try LibraryStore.open(at: store.root))
                XCTAssertThrowsError(try store.createSource(name: "blocked"))
            }
            XCTAssertEqual(try LibraryStore.open(at: store.root).metadata.libraryID, store.metadata.libraryID)
            _ = try store.createSource(name: "unblocked")
        }
    }
    func testRecoveryBeforeAndAfterMove() throws {
        try libraryFixture { _, store, sample in
            let a = try store.createSource(name: "A")
            for alreadyMoved in [false, true] {
                let batch = try store.importData(from: sample)
                let target = store.root.appendingPathComponent("sources/\(a.directoryName)/batches/\(batch.id)")
                let op = MoveOperation(id: LibraryIO.uuid(), batchID: batch.id, from: try LibraryIO.relative(batch.workspace, to: store.root), to: try LibraryIO.relative(target, to: store.root), manifestHash: try LibraryIO.hash(batch.workspace.appendingPathComponent("manifest.json")))
                try LibraryIO.write(op, store.root.appendingPathComponent(".operations/\(op.id).json"))
                if alreadyMoved { try FileManager.default.moveItem(at: batch.workspace, to: target) }
                let reopened = try LibraryStore.open(at: store.root)
                XCTAssertEqual(try reopened.contents().batches.filter { $0.id == batch.id }.count, 1)
                XCTAssertEqual(try reopened.contents().batches.first { $0.id == batch.id }?.source?.id, a.id)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent(".operations").path), [])
            }
        }
    }
    func testRecoveryConflictAndTraversalPreserveFiles() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample), a = try store.createSource(name: "A")
            let target = store.root.appendingPathComponent("sources/\(a.directoryName)/batches/\(batch.id)")
            try SafeFiles.copy(batch.workspace, to: target)
            let op = MoveOperation(id: LibraryIO.uuid(), batchID: batch.id, from: try LibraryIO.relative(batch.workspace, to: store.root), to: try LibraryIO.relative(target, to: store.root), manifestHash: try LibraryIO.hash(batch.workspace.appendingPathComponent("manifest.json")))
            let journal = store.root.appendingPathComponent(".operations/\(op.id).json")
            try LibraryIO.write(op, journal)
            XCTAssertThrowsError(try LibraryStore.open(at: store.root))
            XCTAssertTrue(FileManager.default.fileExists(atPath: batch.workspace.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
            let bad = MoveOperation(id: op.id, batchID: batch.id, from: op.from, to: "../escape", manifestHash: op.manifestHash)
            try LibraryIO.write(bad, journal)
            XCTAssertThrowsError(try LibraryStore.open(at: store.root))
            XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("escape").path))
        }
    }
    func testInterruptedImportRecoveryAndFailedImportCleanup() throws {
        try libraryFixture { temp, store, sample in
            let job = store.root.appendingPathComponent(".staging/import-" + LibraryIO.uuid())
            let pending = try Importer.run(source: sample, inbox: job)
            let op = MoveOperation(id: LibraryIO.uuid(), batchID: pending.manifest.id, from: try LibraryIO.relative(pending.workspace, to: store.root), to: "unfiled/" + pending.manifest.id, manifestHash: try LibraryIO.hash(pending.workspace.appendingPathComponent("manifest.json")))
            try LibraryIO.write(op, store.root.appendingPathComponent(".operations/\(op.id).json"))
            let reopened = try LibraryStore.open(at: store.root)
            XCTAssertEqual(try reopened.contents().batches.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: job.path))
            let invalid = temp.appendingPathComponent("empty"); try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: false)
            XCTAssertThrowsError(try reopened.importData(from: invalid))
            XCTAssertThrowsError(try reopened.importData(from: reopened.root))
            XCTAssertThrowsError(try reopened.importData(from: temp))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent(".staging").path), [])
        }
    }
    func testHandoffIndependentAndScoped() throws {
        try libraryFixture { temp, store, sample in
            let a = try store.createSource(name: "A"), b = try store.createSource(name: "B")
            let batch = try store.importData(from: sample)
            try store.assign(batchID: batch.id, to: a.id)
            let handoff = try store.createHandoff(batchID: batch.id, at: temp.appendingPathComponent("Handoffs + & ?"))
            let hashes = try LibraryIO.hashes(handoff.workspace)
            XCTAssertEqual(handoff.metadata.scope, "single-batch"); XCTAssertEqual(handoff.metadata.sourceID, a.id)
            XCTAssertEqual(handoff.metadata.files, try LibraryIO.hashes(handoff.workspace, excluding: ["handoff.json"]))
            let moved = try store.assign(batchID: batch.id, to: b.id)
            try store.renameSource(id: a.id, name: "A改名", note: "")
            try "external edit".write(to: moved.workspace.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
            XCTAssertEqual(try LibraryIO.hashes(handoff.workspace), hashes)
            let prompt = AgentPrompt.make(workspace: handoff.workspace, for: .summary)
            XCTAssertTrue(prompt.contains("来源：A")); XCTAssertTrue(prompt.contains("本次仅包含这一批")); XCTAssertFalse(prompt.contains("来源：B"))
            let url = try CodexHandoff.makeURL(workspace: handoff.workspace, action: .summary)
            XCTAssertTrue(url.absoluteString.contains("mode=codex")); XCTAssertFalse(url.absoluteString.contains("submit="))
            XCTAssertEqual(try LibraryIO.read(HandoffMetadata.self, handoff.workspace.appendingPathComponent("handoff.json")).batchID, batch.id)
        }
    }
    func testHandoffFailureLeavesNoPartialPackage() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            try FileManager.default.removeItem(at: batch.workspace.appendingPathComponent("messages.jsonl"))
            let output = temp.appendingPathComponent("Handoffs")
            XCTAssertThrowsError(try HandoffPackage.create(workspace: batch.workspace, libraryID: store.metadata.libraryID, source: nil, at: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: batch.workspace.path))
        }
    }
    func testSourceTimestampPrecision() throws {
        try libraryFixture { _, store, sample in
            let batch = try store.importData(from: sample)
            XCTAssertEqual(batch.manifest.firstTimestampOriginal, "2026-9-19 10:37")
            XCTAssertEqual(batch.manifest.lastTimestampOriginal, "2026-9-19 10:38:12")
            let markdown = try String(contentsOf: batch.workspace.appendingPathComponent("transcript.md"), encoding: .utf8)
            XCTAssertTrue(markdown.contains("Alice · 2026-9-19 10:37\n"))

        }
    }
}

extension WeChat2AICoreTests {
    func testManagedProjectReusesWorkspaceAndScopesEachBatch() throws {
        try libraryFixture { temp, store, sample in
            let source = try store.createSource(name: "Agent 测试群 + # & ?")
            let root = temp.appendingPathComponent("Projects")
            var deliveries: [HandoffResult] = []
            for _ in 0..<2 {
                let batch = try store.importData(from: sample)
                try store.assign(batchID: batch.id, to: source.id)
                deliveries.append(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root))
            }
            let first = deliveries[0], second = deliveries[1]
            XCTAssertTrue(first.project != nil)
            XCTAssertEqual(first.project, second.project)
            XCTAssertFalse(first.workspace == second.workspace)
            XCTAssertFalse(first.metadata.batchID == second.metadata.batchID)
            XCTAssertEqual(try ManagedProjects.existing(libraryID: store.metadata.libraryID, sourceID: source.id, at: root), first.project)
            for delivery in deliveries {
                let url = try CodexHandoff.makeURL(workspace: delivery.workspace, action: .summary, project: delivery.project)
                let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                XCTAssertEqual(c.path, "/new")
                XCTAssertEqual(c.queryItems?.map(\.name), ["path", "prompt", "mode"])
                XCTAssertEqual(c.queryItems?.first?.value, delivery.project!.path)
                let prompt = c.queryItems![1].value!
                XCTAssertTrue(prompt.contains(delivery.workspace.appendingPathComponent("transcript.md").path))
                XCTAssertTrue(prompt.contains(delivery.workspace.appendingPathComponent("handoff.json").path))
                XCTAssertFalse(prompt.contains(deliveries.first { $0.workspace != delivery.workspace }!.workspace.path))
                XCTAssertTrue(url.absoluteString.contains("%2B"))
                XCTAssertFalse(url.absoluteString.contains("这是一份虚构的测试记录"))
                XCTAssertEqual(delivery.metadata.files, try LibraryIO.hashes(delivery.workspace, excluding: ["handoff.json"]))
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.project!.appendingPathComponent("wechat-imports").path).count, 2)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.project!.appendingPathComponent("results").path), [])
        }
    }

    func testManagedProjectRenameAndReassignmentPreserveHistory() throws {
        try libraryFixture { temp, store, sample in
            let a = try store.createSource(name: "A群"), b = try store.createSource(name: "B群")
            let root = temp.appendingPathComponent("Projects"), batch = try store.importData(from: sample)
            try store.assign(batchID: batch.id, to: a.id)
            let first = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            let before = try LibraryIO.hashes(first.workspace)
            try "User result".write(to: first.project!.appendingPathComponent("results/notes.md"), atomically: true, encoding: .utf8)
            try store.renameSource(id: a.id, name: "A群新名字", note: "")
            let renamed = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            XCTAssertEqual(renamed.project, first.project)
            XCTAssertEqual(renamed.metadata.sourceName, "A群新名字")
            try store.assign(batchID: batch.id, to: b.id)
            let reassigned = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            XCTAssertFalse(reassigned.project == first.project)
            XCTAssertEqual(try LibraryIO.hashes(first.workspace), before)
            XCTAssertEqual(try String(contentsOf: first.project!.appendingPathComponent("results/notes.md"), encoding: .utf8), "User result")
        }
    }

    func testManagedProjectSeparatesSameNamesAndLibraries() throws {
        try libraryFixture { temp, store, sample in
            let root = temp.appendingPathComponent("Projects"), batch = try store.importData(from: sample)
            var paths = Set<String>()
            for _ in 0..<2 {
                let source = try store.createSource(name: "同名群")
                try store.assign(batchID: batch.id, to: source.id)
                paths.insert(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root).project!.path)
            }
            let other = try LibraryStore.create(at: temp.appendingPathComponent("OtherLibrary"))
            let source = try other.createSource(name: "同名群"), otherBatch = try other.importData(from: sample)
            try other.assign(batchID: otherBatch.id, to: source.id)
            paths.insert(try other.createCodexHandoff(batchID: otherBatch.id, projectsRoot: root).project!.path)
            XCTAssertEqual(paths.count, 3)
            let moved = temp.appendingPathComponent("MovedLibrary")
            try FileManager.default.moveItem(at: store.root, to: moved)
            let reopened = try LibraryStore.open(at: moved)
            XCTAssertTrue(paths.contains(try reopened.createCodexHandoff(batchID: batch.id, projectsRoot: root).project!.path))
        }
    }

    func testManagedProjectMissingOrInvalidDoesNotReplaceFiles() throws {
        try libraryFixture { temp, store, sample in
            let root = temp.appendingPathComponent("Projects"), source = try store.createSource(name: "A")
            let batch = try store.importData(from: sample); try store.assign(batchID: batch.id, to: source.id)
            let first = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root), project = first.project!
            let offline = temp.appendingPathComponent("OfflineProject")
            try FileManager.default.moveItem(at: project, to: offline)
            XCTAssertThrowsError(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root))
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.path))
            try FileManager.default.moveItem(at: offline, to: project)
            let metadataURL = project.appendingPathComponent("project.json"), original = try Data(contentsOf: metadataURL)
            var metadata = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            metadata["schemaVersion"] = 99
            let altered = try JSONSerialization.data(withJSONObject: metadata)
            try altered.write(to: metadataURL)
            XCTAssertThrowsError(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root))
            XCTAssertEqual(try Data(contentsOf: metadataURL), altered)
            try original.write(to: metadataURL)
            let imports = project.appendingPathComponent("wechat-imports")
            try FileManager.default.moveItem(at: imports, to: temp.appendingPathComponent("ExternalImports"))
            try FileManager.default.createSymbolicLink(at: imports, withDestinationURL: temp.appendingPathComponent("ExternalImports"))
            XCTAssertThrowsError(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root))
            XCTAssertTrue(try store.contents().batches.contains { $0.id == batch.id })
        }
    }

    func testManagedProjectRecoversBindingAfterRenameAndRejectsTraversal() throws {
        try libraryFixture { temp, store, sample in
            let root = temp.appendingPathComponent("Projects"), source = try store.createSource(name: "A")
            let batch = try store.importData(from: sample); try store.assign(batchID: batch.id, to: source.id)
            let first = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            let binding = root.appendingPathComponent(store.metadata.libraryID + "/bindings.json")
            try FileManager.default.removeItem(at: binding) // Simulate crash before binding publication.
            try store.renameSource(id: source.id, name: "Renamed", note: "")
            XCTAssertEqual(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root).project, first.project)
            let bad: [String: Any] = ["schemaVersion": 1, "libraryID": store.metadata.libraryID, "sources": [source.id: "../outside"]]
            try JSONSerialization.data(withJSONObject: bad).write(to: binding)
            XCTAssertThrowsError(try store.createCodexHandoff(batchID: batch.id, projectsRoot: root))
            XCTAssertThrowsError(try ManagedProjects.existing(libraryID: store.metadata.libraryID, sourceID: source.id, at: root))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
        }
    }

    func testUnfiledHandoffAndProjectURLMismatch() throws {
        try libraryFixture { temp, store, sample in
            let projects = temp.appendingPathComponent("Projects"), handoffs = temp.appendingPathComponent("Handoffs")
            let batch = try store.importData(from: sample)
            let unfiled = try store.createCodexHandoff(batchID: batch.id, projectsRoot: projects, handoffRoot: handoffs)
            XCTAssertNil(unfiled.project)
            XCTAssertNil(unfiled.project)
            XCTAssertFalse(FileManager.default.fileExists(atPath: projects.path))
            let source = try store.createSource(name: "A")
            try store.assign(batchID: batch.id, to: source.id)
            let grouped = try store.createCodexHandoff(batchID: batch.id, projectsRoot: projects)
            XCTAssertThrowsError(try CodexHandoff.makeURL(workspace: unfiled.workspace, action: .summary, project: grouped.project))
            XCTAssertThrowsError(try CodexHandoff.makeURL(workspace: grouped.workspace, action: .summary, project: URL(string: "https://example.com")!))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unfiled.workspace.path))
        }
    }
}

extension WeChat2AICoreTests {
    func testAnalysisComparisonSnapshotsOnlySelectedSameGroup() throws {
        try libraryFixture { temp, store, sample in
            let source = try store.createSource(name: "测试群"), root = temp.appendingPathComponent("Projects")
            var batches: [LibraryBatch] = []
            for _ in 0..<3 {
                let b = try store.importData(from: sample)
                batches.append(try store.assign(batchID: b.id, to: source.id))
            }
            let delivery = try store.createAnalysisHandoff(batchID: batches[0].id, task: AnalysisTask(action: .compare), historyIDs: [batches[1].id], projectsRoot: root)
            let manifest = try LibraryIO.read(AnalysisTaskManifest.self, delivery.workspace.appendingPathComponent("task.json"))
            XCTAssertEqual(manifest.primaryBatchID, batches[0].id)
            XCTAssertEqual(manifest.references.map(\.batchID), [batches[1].id])
            XCTAssertEqual(delivery.metadata.scope, "primary-with-selected-context")
            XCTAssertEqual(delivery.metadata.files, try LibraryIO.hashes(delivery.workspace, excluding: ["handoff.json"]))
            let snapshot = delivery.workspace.appendingPathComponent(manifest.references[0].relativePath)
            let before = try LibraryIO.hashes(snapshot)
            try "changed historical record".write(to: batches[1].workspace.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
            XCTAssertEqual(try LibraryIO.hashes(snapshot), before)
            let prompt = AgentPrompt.make(workspace: delivery.workspace, for: .compare, project: delivery.project)
            XCTAssertTrue(prompt.contains("task.json")); XCTAssertTrue(prompt.contains("用户明确选择的参考资料"))
            XCTAssertFalse(prompt.contains("本次仅包含这一批资料"))
            XCTAssertFalse(prompt.contains(batches[2].id))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: delivery.project!.appendingPathComponent("wechat-imports").path).count, 1)
        }
    }
    func testAnalysisRejectsEmptyForeignDuplicateContextAndCleansUp() throws {
        try libraryFixture { temp, store, sample in
            let a = try store.createSource(name: "A"), b = try store.createSource(name: "B"), root = temp.appendingPathComponent("Projects")
            let first = try store.importData(from: sample), other = try store.importData(from: sample)
            try store.assign(batchID: first.id, to: a.id); try store.assign(batchID: other.id, to: b.id)
            let base = try store.createCodexHandoff(batchID: first.id, projectsRoot: root)
            let imports = base.project!.appendingPathComponent("wechat-imports")
            let before = try FileManager.default.contentsOfDirectory(atPath: imports.path)
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .compare), projectsRoot: root))
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .compare), historyIDs: [other.id], projectsRoot: root))
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .compare), historyIDs: [first.id], projectsRoot: root))
            try store.assign(batchID: other.id, to: a.id)
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .compare), historyIDs: [other.id, other.id], projectsRoot: root))
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .summary), historyIDs: [other.id], projectsRoot: root))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imports.path), before)
            XCTAssertEqual(try store.contents().batches.count, 2)
        }
    }
    func testAnalysisConclusionSelectedResultsAreSnapshotsAndReadOnly() throws {
        try libraryFixture { temp, store, sample in
            let source = try store.createSource(name: "测试群"), root = temp.appendingPathComponent("Projects")
            let batch = try store.importData(from: sample); try store.assign(batchID: batch.id, to: source.id)
            let base = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            let results = base.project!.appendingPathComponent("results")
            let selected = results.appendingPathComponent("结论.md"), excluded = results.appendingPathComponent("未选.txt")
            try "历史结论：待验证".write(to: selected, atomically: true, encoding: .utf8)
            try "EXCLUDED_MARKER".write(to: excluded, atomically: true, encoding: .utf8)
            let delivery = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .conclusions), resultFiles: [selected], projectsRoot: root)
            let manifest = try LibraryIO.read(AnalysisTaskManifest.self, delivery.workspace.appendingPathComponent("task.json"))
            XCTAssertEqual(manifest.references.count, 1); XCTAssertEqual(manifest.references[0].kind, "result-file")
            let copy = delivery.workspace.appendingPathComponent(manifest.references[0].relativePath)
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "历史结论：待验证")
            XCTAssertEqual(try String(contentsOf: selected, encoding: .utf8), "历史结论：待验证")
            try "User updated result".write(to: selected, atomically: true, encoding: .utf8)
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "历史结论：待验证")
            XCTAssertTrue(manifest.outputPolicy.contains("reply-only"))
            let url = try CodexHandoff.makeURL(workspace: delivery.workspace, action: .conclusions, project: delivery.project)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.map(\.name), ["path", "prompt", "mode"])
            XCTAssertTrue(items[1].value!.contains("写入或覆盖项目文件前请先由我确认"))
            XCTAssertFalse(items[1].value!.contains("EXCLUDED_MARKER"))
        }
    }
    func testAnalysisResultEscapeAndLargeInputsAreRejected() throws {
        try libraryFixture { temp, store, sample in
            let source = try store.createSource(name: "A"), root = temp.appendingPathComponent("Projects")
            let batch = try store.importData(from: sample); try store.assign(batchID: batch.id, to: source.id)
            let base = try store.createCodexHandoff(batchID: batch.id, projectsRoot: root)
            let outside = temp.appendingPathComponent("Outside.md")
            try "outside".write(to: outside, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .conclusions), resultFiles: [outside], projectsRoot: root))
            let link = base.project!.appendingPathComponent("results/link.md")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .conclusions), resultFiles: [link], projectsRoot: root))
            let large = base.project!.appendingPathComponent("results/large.md")
            FileManager.default.createFile(atPath: large.path, contents: nil)
            let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: 21 * 1024 * 1024); try handle.close()
            XCTAssertThrowsError(try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .conclusions), resultFiles: [large], projectsRoot: root))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.project!.appendingPathComponent("wechat-imports").path).count, 1)
            XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "outside")
        }
    }
    func testTaskTemplatesDefaultsAndCorruptionProtection() throws {
        try libraryFixture { temp, store, _ in
            let file = temp.appendingPathComponent("tasks.json"), a = try store.createSource(name: "同名"), b = try store.createSource(name: "同名")
            var settings = TaskSettings()
            let template = TaskTemplate(id: UUID().uuidString.lowercased(), title: "我的需求整理", instruction: "优先整理交互流程和待确认需求。")
            settings.templates.append(template)
            let aKey = TaskSettings.sourceKey(libraryID: store.metadata.libraryID, sourceID: a.id)
            let bKey = TaskSettings.sourceKey(libraryID: store.metadata.libraryID, sourceID: b.id)
            settings.sourceDefaults[aKey] = "template:" + template.id
            settings.sourceDefaults[bKey] = TaskSettings.builtinKey(.requirements)
            try settings.save(at: file)
            var restored = try TaskSettings.load(at: file)
            XCTAssertEqual(try restored.resolve(restored.sourceDefaults[aKey]!).instruction, template.instruction)
            XCTAssertEqual(try restored.resolve(restored.sourceDefaults[bKey]!).action, .requirements)
            try store.renameSource(id: a.id, name: "新名字", note: "")
            XCTAssertEqual(try TaskSettings.load(at: file).sourceDefaults[aKey], "template:" + template.id)
            restored.templates[0].instruction = "更新后的要求"; try restored.save(at: file)
            XCTAssertEqual(try TaskSettings.load(at: file).resolve("template:" + template.id).instruction, "更新后的要求")
            restored.sourceDefaults.removeValue(forKey: aKey); try restored.save(at: file)
            XCTAssertNil(try TaskSettings.load(at: file).sourceDefaults[aKey])
            let unsupported = Data("{\"schemaVersion\":99,\"templates\":[],\"sourceDefaults\":{}}".utf8)
            try unsupported.write(to: file)
            XCTAssertThrowsError(try TaskSettings.load(at: file)); XCTAssertThrowsError(try settings.save(at: file))
            XCTAssertEqual(try Data(contentsOf: file), unsupported)
        }
    }
    func testTaskCustomRequirementsAndRawHandoffContracts() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample), output = temp.appendingPathComponent("Handoffs")
            let custom = AnalysisTask(action: .custom, title: "定制任务", instruction: "CUSTOM_TASK + & # ?\n请按使用场景整理。")
            let delivery = try store.createAnalysisHandoff(batchID: batch.id, task: custom, handoffRoot: output)
            let url = try CodexHandoff.makeURL(workspace: delivery.workspace, action: .custom)
            let prompt = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems![1].value!
            XCTAssertTrue(prompt.contains(custom.instruction)); XCTAssertTrue(prompt.contains("task.json"))
            XCTAssertFalse(url.absoluteString.contains("submit="))
            let raw = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .raw), handoffRoot: output)
            XCTAssertTrue(AgentPrompt.make(workspace: raw.workspace, for: .raw).contains("等待我补充具体分析要求"))
            let requirements = ChatAction.requirements.instruction
            XCTAssertTrue(requirements.contains("已明确同意")); XCTAssertTrue(requirements.contains("原文依据"))
            XCTAssertTrue(requirements.contains("未明确")); XCTAssertTrue(requirements.contains("验收条件"))
            XCTAssertThrowsError(try AnalysisTask(action: .custom, instruction: " ").validate())
            XCTAssertThrowsError(try AnalysisTask(action: .custom, instruction: String(repeating: "X", count: 4001)).validate())
        }
    }
}


extension WeChat2AICoreTests {
    func testDesktopAgentsShareGroupProjectAndImmutableContext() throws {
        try libraryFixture { temp, store, sample in
            let source = try store.createSource(name: "共用群 + & #"), projects = temp.appendingPathComponent("Shared Projects")
            let first = try store.importData(from: sample), second = try store.importData(from: sample)
            let original = try store.assign(batchID: first.id, to: source.id)
            try store.assign(batchID: second.id, to: source.id)
            let sourceHash = try LibraryIO.hashes(original.workspace)
            let claude = try store.createAnalysisHandoff(batchID: first.id, task: AnalysisTask(action: .requirements), projectsRoot: projects)
            let saved = claude.project!.appendingPathComponent("results/prior.md")
            try "Existing user result".write(to: saved, atomically: true, encoding: .utf8)
            let firstHash = try LibraryIO.hashes(claude.workspace)
            let codex = try store.createAnalysisHandoff(batchID: second.id, task: AnalysisTask(action: .conclusions), historyIDs: [first.id], resultFiles: [saved], projectsRoot: projects)
            XCTAssertEqual(claude.project, codex.project)
            XCTAssertFalse(claude.workspace == codex.workspace)
            let c = URLComponents(url: try AgentTarget.claudeCode.makeURL(workspace: claude.workspace, action: .requirements, project: claude.project), resolvingAgainstBaseURL: false)!
            let x = URLComponents(url: try AgentTarget.codex.makeURL(workspace: codex.workspace, action: .conclusions, project: codex.project), resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.queryItems!.first!.value, x.queryItems!.first!.value)
            XCTAssertTrue(c.queryItems![1].value!.contains(ChatAction.requirements.instruction))
            XCTAssertTrue(x.queryItems![1].value!.contains("task.json"))
            XCTAssertEqual(try LibraryIO.read(AnalysisTaskManifest.self, codex.workspace.appendingPathComponent("task.json")).references.count, 2)
            XCTAssertEqual(try LibraryIO.hashes(original.workspace), sourceHash)
            XCTAssertEqual(try LibraryIO.hashes(claude.workspace), firstHash)
            XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Existing user result")
            let folders = try FileManager.default.contentsOfDirectory(at: claude.project!.deletingLastPathComponent(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            XCTAssertEqual(folders.filter { $0.lastPathComponent != "bindings.json" }.count, 1)
        }
    }

    func testClaudeURLRoundTripAndUnfiledFallback() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            let task = AnalysisTask(action: .custom, instruction: "中文 + & # ? %\n测试要求")
            let handoff = try store.createAnalysisHandoff(batchID: batch.id, task: task, handoffRoot: temp.appendingPathComponent("未归群 + & # ? %"))
            let url = try ClaudeCodeHandoff.makeURL(workspace: handoff.workspace, action: .custom)
            let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.scheme, "claude"); XCTAssertEqual(c.host, "code"); XCTAssertEqual(c.path, "/new")
            XCTAssertEqual(c.queryItems!.map(\.name), ["folder", "q"])
            XCTAssertEqual(c.queryItems![0].value, handoff.workspace.standardizedFileURL.path)
            XCTAssertTrue(c.queryItems![1].value!.contains(task.instruction))
            XCTAssertFalse(c.percentEncodedQuery!.contains("+")); XCTAssertNil(c.fragment)
            XCTAssertFalse(c.queryItems![1].value!.contains(try String(contentsOf: handoff.workspace.appendingPathComponent("transcript.md"), encoding: .utf8)))
            XCTAssertNil(handoff.project)
            XCTAssertThrowsError(try ClaudeCodeHandoff.makeURL(workspace: URL(string: "https://example.com")!, action: .summary))
            XCTAssertThrowsError(try ClaudeCodeHandoff.makeURL(workspace: temp.appendingPathComponent("missing"), action: .summary))
            let group = try store.createSource(name: "Other")
            try store.assign(batchID: batch.id, to: group.id)
            let grouped = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .raw), projectsRoot: temp.appendingPathComponent("Projects"))
            XCTAssertThrowsError(try ClaudeCodeHandoff.makeURL(workspace: handoff.workspace, action: .summary, project: grouped.project))
            XCTAssertTrue(try ClaudeCodeHandoff.prefill(workspace: grouped.workspace, action: .raw).contains("等待我补充具体分析要求"))
        }
    }

    func testClaudeLongTaskUsesCompleteManifestAndRejectsUnknownVersion() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            // Each grapheme uses 11 UTF-16 units; under task's character cap, over desktop prefill cap.
            let task = AnalysisTask(action: .custom, instruction: String(repeating: "👨‍👩‍👧‍👦", count: 1500))
            let handoff = try store.createAnalysisHandoff(batchID: batch.id, task: task, handoffRoot: temp.appendingPathComponent("Handoffs"))
            let before = try LibraryIO.hashes(handoff.workspace)
            XCTAssertTrue(AgentPrompt.make(workspace: handoff.workspace, for: .custom).utf16.count > ClaudeCodeHandoff.maximumPromptUTF16)
            let text = try ClaudeCodeHandoff.prefill(workspace: handoff.workspace, action: .custom)
            XCTAssertTrue(text.utf16.count <= ClaudeCodeHandoff.maximumPromptUTF16)
            XCTAssertTrue(text.contains(handoff.workspace.appendingPathComponent("task.json").path))
            XCTAssertTrue(text.contains("task.instruction")); XCTAssertTrue(text.contains("references"))
            let file = handoff.workspace.appendingPathComponent("task.json")
            var manifest = try LibraryIO.read(AnalysisTaskManifest.self, file)
            XCTAssertEqual(manifest.task.instruction, task.instruction)
            XCTAssertEqual(try LibraryIO.hashes(handoff.workspace), before)
            manifest.schemaVersion = 99; try LibraryIO.write(manifest, file)
            XCTAssertThrowsError(try ClaudeCodeHandoff.makeURL(workspace: handoff.workspace, action: .custom))
        }
    }

    func testDesktopMissingAppCreatesNothingAndLinkFailurePreservesSnapshot() throws {
        var called = false
        XCTAssertThrowsError(try DesktopLaunch.prepare(target: .claudeCode, application: nil, action: .summary) {
            called = true; throw CoreError.invalid("must not run")
        })
        XCTAssertFalse(called)
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            let handoff = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .summary), handoffRoot: temp.appendingPathComponent("Handoffs"))
            let app = temp.appendingPathComponent("Mock Claude.app")
            let launch = try DesktopLaunch.prepare(target: .claudeCode, application: app, action: .summary) { handoff }
            XCTAssertEqual(launch.application, app); XCTAssertEqual(launch.handoff.workspace, handoff.workspace)
            // Simulate a completed snapshot whose task format the destination cannot accept.
            let file = handoff.workspace.appendingPathComponent("task.json")
            var manifest = try LibraryIO.read(AnalysisTaskManifest.self, file); manifest.schemaVersion = 99
            try LibraryIO.write(manifest, file)
            let before = try LibraryIO.hashes(handoff.workspace)
            XCTAssertThrowsError(try DesktopLaunch.prepare(target: .claudeCode, application: app, action: .summary) { handoff })
            XCTAssertEqual(try LibraryIO.hashes(handoff.workspace), before)
            // Generic copy doesn't need an installed app or construct a destination URL.
            XCTAssertTrue(AgentPrompt.make(workspace: handoff.workspace, for: .summary).contains("transcript.md"))
        }
    }

    func testAgentPreferenceAndAllTaskPromptsRemainIndependent() throws {
        let name = "WeChat2AI.QA." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        XCTAssertEqual(AgentTarget.restored(prefs.string(forKey: AgentTarget.preferenceKey)), .codex)
        prefs.set(AgentTarget.claudeCode.rawValue, forKey: AgentTarget.preferenceKey)
        XCTAssertEqual(AgentTarget.restored(UserDefaults(suiteName: name)!.string(forKey: AgentTarget.preferenceKey)), .claudeCode)
        XCTAssertEqual(AgentTarget.restored("futureAgent"), .codex)
        XCTAssertEqual(AgentTarget.claudeCode.bundleIdentifier, "com.anthropic.claudefordesktop")
        XCTAssertEqual(TaskDelivery.desktop(.claudeCode).agent, .claudeCode); XCTAssertNil(TaskDelivery.copy.agent)
        for action in ChatAction.allCases {
            let directory = URL(fileURLWithPath: "/tmp/Synthetic")
            XCTAssertEqual(try ClaudeCodeHandoff.prefill(workspace: directory, action: action), AgentPrompt.make(workspace: directory, for: action))
        }
    }
}


extension WeChat2AICoreTests {
    func testCoworkUsesSharedFolderAndRelativeScope() throws {
        try libraryFixture { temp, store, sample in
            let group = try store.createSource(name: "共享群 + & #")
            let batch = try store.importData(from: sample), history = try store.importData(from: sample)
            try store.assign(batchID: batch.id, to: group.id)
            try store.assign(batchID: history.id, to: group.id)
            let projects = temp.appendingPathComponent("Projects + & # 中文")
            let code = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .summary), projectsRoot: projects)
            let cowork = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .compare), historyIDs: [history.id], projectsRoot: projects)
            let before = try LibraryIO.hashes(cowork.workspace)
            let c = URLComponents(url: try AgentTarget.claudeCowork.makeURL(workspace: cowork.workspace, action: .compare, project: cowork.project), resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.scheme, "claude"); XCTAssertEqual(c.host, "cowork"); XCTAssertEqual(c.path, "/new")
            XCTAssertEqual(c.queryItems!.map(\.name), ["folder", "q"])
            XCTAssertEqual(c.queryItems![0].value, code.project!.path)
            XCTAssertEqual(code.project, cowork.project); XCTAssertFalse(code.workspace == cowork.workspace)
            let text = c.queryItems![1].value!
            XCTAssertTrue(text.contains("wechat-imports/" + cowork.workspace.lastPathComponent))
            XCTAssertFalse(text.contains(cowork.project!.path))
            XCTAssertTrue(text.contains(ChatAction.compare.instruction)); XCTAssertTrue(text.contains("references"))
            XCTAssertFalse(text.contains(try String(contentsOf: cowork.workspace.appendingPathComponent("transcript.md"), encoding: .utf8)))
            XCTAssertFalse(c.percentEncodedQuery!.contains("+")); XCTAssertNil(c.fragment)
            XCTAssertEqual(try LibraryIO.hashes(cowork.workspace), before)
            XCTAssertThrowsError(try ClaudeCoworkHandoff.makeURL(workspace: temp.appendingPathComponent("missing"), action: .summary))
            XCTAssertThrowsError(try ClaudeCoworkHandoff.makeURL(workspace: cowork.workspace, action: .summary, project: temp))
        }
    }

    func testCoworkUnfiledLongTaskAndManifestFailure() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            let task = AnalysisTask(action: .custom, instruction: String(repeating: "👨‍👩‍👧‍👦", count: 1500))
            let handoff = try store.createAnalysisHandoff(batchID: batch.id, task: task, handoffRoot: temp.appendingPathComponent("Handoffs"))
            let c = URLComponents(url: try ClaudeCoworkHandoff.makeURL(workspace: handoff.workspace, action: .custom), resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.queryItems![0].value, handoff.workspace.path)
            let text = c.queryItems![1].value!
            XCTAssertTrue(text.contains("本次数据子目录：."))
            XCTAssertTrue(text.contains("task.instruction"))
            XCTAssertTrue(text.utf16.count <= ClaudeCodeHandoff.maximumPromptUTF16)
            let file = handoff.workspace.appendingPathComponent("task.json")
            var manifest = try LibraryIO.read(AnalysisTaskManifest.self, file)
            XCTAssertEqual(manifest.task.instruction, task.instruction)
            manifest.schemaVersion = 99; try LibraryIO.write(manifest, file)
            let before = try LibraryIO.hashes(handoff.workspace)
            XCTAssertThrowsError(try DesktopLaunch.prepare(target: .claudeCowork, application: temp.appendingPathComponent("Claude.app"), action: .custom) { handoff })
            XCTAssertEqual(try LibraryIO.hashes(handoff.workspace), before)
            let raw = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .raw), handoffRoot: temp.appendingPathComponent("Handoffs"))
            XCTAssertTrue(try ClaudeCoworkHandoff.prefill(workspace: raw.workspace, action: .raw).contains("等待我补充具体分析要求"))
        }
    }

    func testThreeIndependentAgentPickerOptions() throws {
        XCTAssertEqual(AgentTarget.pickerTargets, [.codex, .claudeCode, .claudeCowork])
        XCTAssertEqual(AgentTarget.restored("claudeCowork"), .claudeCowork)
        XCTAssertEqual(AgentTarget.claudeCowork.bundleIdentifier, AgentTarget.claudeCode.bundleIdentifier)
        XCTAssertEqual(TaskDelivery.desktop(.claudeCowork).agent, .claudeCowork)
        var created = false
        XCTAssertThrowsError(try DesktopLaunch.prepare(target: .claudeCowork, application: nil, action: .summary) {
            created = true; throw CoreError.invalid("must not create")
        })
        XCTAssertFalse(created)
    }
}


extension WeChat2AICoreTests {







    func testAgentWorkspaceDefaultsAndIndependentHandoff() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WeChat2AI")
        XCTAssertEqual(LibraryStore.defaultRoot.path, support.appendingPathComponent("Library").path)
        XCTAssertEqual(Importer.defaultOutputRoot.path, support.appendingPathComponent("Imports").path)
        XCTAssertEqual(TaskSettings.defaultURL.path, support.appendingPathComponent("task-settings.json").path)
        XCTAssertEqual(AgentWorkspace.root.lastPathComponent, "WeChat2AI")
        XCTAssertEqual(ManagedProjects.defaultRoot.path, AgentWorkspace.root.appendingPathComponent("Projects").path)
        XCTAssertEqual(HandoffPackage.defaultRoot.path, AgentWorkspace.root.appendingPathComponent("Handoffs").path)
        XCTAssertFalse(AgentWorkspace.root.path.hasPrefix(StoragePaths.applicationSupport.path))
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            let root = temp.appendingPathComponent("Work/Handoffs")
            let result = try store.createAnalysisHandoff(batchID: batch.id, task: AnalysisTask(action: .summary), handoffRoot: root)
            XCTAssertNil(result.project); XCTAssertEqual(result.workspace.deletingLastPathComponent().path, root.path)
        }
    }
}

extension WeChat2AICoreTests {


}


extension WeChat2AICoreTests {
    func testTemplateRemovalClearsOnlyItsDefaults() throws {
        try libraryFixture { temp, store, sample in
            let batch = try store.importData(from: sample)
            let before = try LibraryIO.hashes(batch.workspace)
            let a = TaskTemplate(id: UUID().uuidString.lowercased(), title: "待删除模板", instruction: "请总结资料")
            let b = TaskTemplate(id: UUID().uuidString.lowercased(), title: "保留历史模板", instruction: "对比差异", action: .compare)
            let first = TaskSettings.sourceKey(libraryID: UUID().uuidString, sourceID: UUID().uuidString)
            let second = TaskSettings.sourceKey(libraryID: UUID().uuidString, sourceID: UUID().uuidString)
            let untouched = TaskSettings.sourceKey(libraryID: UUID().uuidString, sourceID: UUID().uuidString)
            var settings = TaskSettings(); settings.templates = [a, b]
            settings.sourceDefaults = [first: "template:" + a.id, second: "template:" + a.id, untouched: "template:" + b.id]
            let file = temp.appendingPathComponent("settings.json")
            try settings.save(at: file)
            XCTAssertEqual(try settings.removeTemplate(id: a.id), 2)
            try settings.save(at: file)
            let loaded = try TaskSettings.load(at: file)
            XCTAssertEqual(loaded.templates.map(\.id), [b.id]); XCTAssertNil(loaded.sourceDefaults[first]); XCTAssertNil(loaded.sourceDefaults[second])
            XCTAssertEqual(loaded.sourceDefaults[untouched], "template:" + b.id)
            XCTAssertEqual(try loaded.resolve("template:" + b.id).action, .compare)
            XCTAssertThrowsError(try settings.removeTemplate(id: a.id))
            XCTAssertEqual(try LibraryIO.hashes(batch.workspace), before)
        }
    }
}
