import Foundation

final class WeChat2AICoreTests {
    private var temp: URL!
    func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }

    func testEnglishAndChineseDatesAndMultiline() {
        let parsed = TranscriptParser.parse("\u{feff}·甲\r\n2026-9-19 10:33\r\n第一段\r\n\r\n第二段\r\n\r\n·乙\r\n2026年9月19日 10:34\r\n[图片] 图.jpg\r\n")
        XCTAssertEqual(parsed.messages.count, 2)
        XCTAssertEqual(parsed.messages[0].body, "第一段\n\n第二段")
        XCTAssertEqual(parsed.messages[0].timestamp, "2026-09-19 10:33:00")
        XCTAssertEqual(parsed.messages[1].attachmentName, "图.jpg")
        XCTAssertTrue(parsed.warnings.isEmpty)
    }
    func testEnglishMediaAndEmoji() {
        let parsed = TranscriptParser.parse("·A\n2026-9-19 10:37\n[Photo] Weixin Image_1.jpg\n\n·B\n2026-9-19 10:38\n[ThumbsUp][ThumbsUp]")
        XCTAssertEqual(parsed.messages.map(\.kind), ["image", "text"])
    }
    func testRawFallbackAndInvalidDate() {
        let input = "·A\n2026-2-30 10:37\n内容"
        let parsed = TranscriptParser.parse(input)
        XCTAssertEqual(parsed.messages.count, 0)
        XCTAssertEqual(parsed.unparsedPrefix, input)
        XCTAssertFalse(parsed.warnings.isEmpty)
    }
    func testPrefixPreservedAndTimestampLikeBody() {
        let parsed = TranscriptParser.parse("标题\n·A\n2026-9-19 10:37\n提醒\n2026-9-20 10:37\n内容")
        XCTAssertEqual(parsed.unparsedPrefix, "标题")
        XCTAssertEqual(parsed.messages.count, 1)
        XCTAssertTrue(parsed.messages[0].body.contains("2026-9-20"))
    }
    private func sample() throws -> URL {
        let source = temp.appendingPathComponent("Sample")
        let media = source.appendingPathComponent("Images, videos, and files in chat history")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try "·Alice\n2026-9-19 10:37\n[Photo] demo image.jpg\n\n·Bob\n2026-9-19 10:38\n第一段\n\n第二段".write(to: source.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
        try Data([1,2,3]).write(to: media.appendingPathComponent("demo image.jpg"))
        return source
    }
    func testImportLinksMediaAndPreservesOriginal() throws {
        let source = try sample()
        let result = try Importer.run(source: source, inbox: temp.appendingPathComponent("Inbox"))
        XCTAssertEqual(result.manifest.messageCount, 2)
        XCTAssertEqual(result.manifest.linkedAttachmentCount, 1)
        XCTAssertEqual(result.manifest.parseStatus, "parsed")
        XCTAssertNil(result.manifest.timezone)
        XCTAssertTrue(result.markdown.contains("demo%20image.jpg"))
        XCTAssertEqual(try Data(contentsOf: result.workspace.appendingPathComponent(result.manifest.transcriptPath)), try Data(contentsOf: source.appendingPathComponent("Chat History.txt")))
        let jsonl = try String(contentsOf: result.workspace.appendingPathComponent("messages.jsonl"), encoding: .utf8)
        XCTAssertEqual(jsonl.split(separator: "\n").count, 2)
    }
    func testDeflatedZIPRoundTrip() throws {
        let source = try sample()
        let archive = temp.appendingPathComponent("sample.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", source.path, archive.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let result = try Importer.run(source: archive, inbox: temp.appendingPathComponent("Inbox"))
        XCTAssertEqual(result.manifest.messageCount, 2)
        XCTAssertEqual(result.manifest.linkedAttachmentCount, 1)
    }
    func testFailedImportLeavesNoPartialWorkspace() throws {
        let empty = temp.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let inbox = temp.appendingPathComponent("Inbox")
        XCTAssertThrowsError(try Importer.run(source: empty, inbox: inbox))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), [])
    }
    func testMissingAndAmbiguousAttachments() throws {
        let source = try sample()
        try FileManager.default.removeItem(at: source.appendingPathComponent("Images, videos, and files in chat history/demo image.jpg"))
        let missing = try Importer.run(source: source, inbox: temp.appendingPathComponent("Inbox"))
        XCTAssertEqual(missing.manifest.parseStatus, "needs-review")
        XCTAssertEqual(missing.manifest.linkedAttachmentCount, 0)
        for name in ["one", "two"] {
            let folder = source.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("demo image.jpg"))
        }
        let ambiguous = try Importer.run(source: source, inbox: temp.appendingPathComponent("Inbox"))
        XCTAssertEqual(ambiguous.manifest.linkedAttachmentCount, 0)
        XCTAssertTrue(ambiguous.manifest.warnings[0].contains("重名"))
    }
    func testSymlinkRejected() throws {
        let source = try sample()
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "/etc/passwd")
        XCTAssertThrowsError(try Importer.run(source: source, inbox: temp.appendingPathComponent("Inbox")))
    }
    /// Generate a tiny stored ZIP to test paths without any extractor on the test side.
    private func storedZIP(_ name: String, attributes: UInt32 = 0, checksum: UInt32 = 0) -> Data {
        func bytes(_ n: UInt32, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: n >> ($0*8)) }) }
        let filename = Data(name.utf8)
        var local = bytes(0x04034b50, 4)
        for value: UInt32 in [20, 0x800, 0, 0, 0] { local += bytes(value, 2) }
        local += bytes(checksum, 4); local += bytes(0, 4); local += bytes(0, 4)
        local += bytes(UInt32(filename.count), 2); local += bytes(0, 2); local += filename
        var central = bytes(0x02014b50, 4)
        for value: UInt32 in [0x314, 20, 0x800, 0, 0, 0] { central += bytes(value, 2) }
        central += bytes(checksum, 4); central += bytes(0, 4); central += bytes(0, 4)
        for value: UInt32 in [UInt32(filename.count), 0, 0, 0, 0] { central += bytes(value, 2) }
        central += bytes(attributes, 4); central += bytes(0, 4); central += filename
        var end = bytes(0x06054b50, 4)
        for value: UInt32 in [0,0,1,1] { end += bytes(value, 2) }
        end += bytes(UInt32(central.count), 4); end += bytes(UInt32(local.count), 4); end += bytes(0, 2)
        return local + central + end
    }
    func testZIPTraversalSymlinkAndCRCRejected() throws {
        for (index, data) in [storedZIP("../escape.txt"), storedZIP("/absolute.txt"), storedZIP("link", attributes: 0xa1ff0000), storedZIP("bad.txt", checksum: 123)].enumerated() {
            let source = temp.appendingPathComponent("bad\(index).zip")
            try data.write(to: source)
            XCTAssertThrowsError(try SafeZIP.extract(source, to: temp.appendingPathComponent("out\(index)")))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("escape.txt").path))
    }
    func testStoredZIPAndTruncation() throws {
        let source = temp.appendingPathComponent("ok.zip")
        let data = storedZIP("folder/empty.txt")
        try data.write(to: source)
        let output = temp.appendingPathComponent("out")
        try SafeZIP.extract(source, to: output)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("folder/empty.txt")).count, 0)
        try data.prefix(16).write(to: source)
        XCTAssertThrowsError(try SafeZIP.extract(source, to: temp.appendingPathComponent("bad")))
    }
    func testSharePackageRoundTrip() throws {
        let source = try sample()
        let package = temp.appendingPathComponent("received.w2adrop")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try SafeFiles.copy(source, to: package.appendingPathComponent("01"))
        let result = try Importer.run(source: package, inbox: temp.appendingPathComponent("Inbox"))
        XCTAssertEqual(result.manifest.messageCount, 2)
        XCTAssertEqual(result.manifest.linkedAttachmentCount, 1)
    }
}

extension WeChat2AICoreTests {
    private func intakeFixture(_ name: String = "Queue") throws -> (IntakeQueue, IntakeJob) {
        let queue = try IntakeQueue.create(at: temp.appendingPathComponent(name))
        let draft = try queue.begin()
        try "·Tester\n2026-9-19 12:00\n[File] example.md".write(to: draft.payload.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
        try "fixture only".write(to: draft.payload.appendingPathComponent("example.md"), atomically: true, encoding: .utf8)
        _ = try queue.publish(draft)
        return (queue, try queue.jobs()[0])
    }
    private func intakeLibrary(_ name: String = "Library") throws -> LibraryStore { try LibraryStore.create(at: temp.appendingPathComponent(name)) }
    private func intakeTarget(_ library: LibraryStore) -> IntakeTarget { IntakeTarget(libraryID: library.metadata.libraryID, path: library.root.path) }

    func testIntakeRoundTripAndDuplicateNotification() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        let result = try IntakeProcessor.process(job.id, in: queue, defaultTarget: intakeTarget(library))
        XCTAssertEqual(try library.contents().batches.count, 1)
        XCTAssertEqual(try queue.jobs().count, 0)
        XCTAssertTrue(try queue.completion(job.id) != nil)
        XCTAssertEqual(try IntakeIO.inventory(result.batch!.workspace.appendingPathComponent("original/payload.w2adrop")), job.receipt!.files)
        let duplicate = try IntakeProcessor.process(job.id, in: queue, defaultTarget: nil)
        XCTAssertEqual(duplicate.completion.batchID, result.completion.batchID)
        XCTAssertEqual(try library.contents().batches.count, 1)
        let handoff = try library.createHandoff(batchID: result.batch!.id, at: temp.appendingPathComponent("Handoffs"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: handoff.workspace.appendingPathComponent("original/payload.w2adrop/example.md").path))
    }
    func testIntakeCrashAfterCommitAndArchive() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        var receipt = job.receipt!; receipt.target = intakeTarget(library)
        try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
        let committed = try library.importIntake(from: job.payload, receipt: receipt)
        // Simulate a crash after library commit but before queue acknowledgement, then archive it.
        let source = try library.createSource(name: "Fixture", note: "", kind: "group")
        _ = try library.assign(batchID: committed.id, to: source.id)
        let resumed = try IntakeProcessor.process(job.id, in: IntakeQueue(at: queue.root), defaultTarget: nil)
        XCTAssertEqual(resumed.completion.batchID, committed.id)
        XCTAssertEqual(try library.contents().batches.count, 1)
        XCTAssertEqual(try queue.jobs().count, 0)
    }
    func testIntakeAcknowledgedCleanupCanResume() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        var receipt = job.receipt!; receipt.target = intakeTarget(library)
        try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
        let batch = try library.importIntake(from: job.payload, receipt: receipt)
        let completion = IntakeCompletion(receipt: receipt, batchID: batch.id)
        try IntakeIO.write(completion, at: queue.root.appendingPathComponent("completed/\(job.id).json"))
        // Crash midway through recursive cleanup; remaining verified files may be removed on recovery.
        try FileManager.default.removeItem(at: job.payload.appendingPathComponent("example.md"))
        _ = try IntakeProcessor.process(job.id, in: queue, defaultTarget: nil)
        XCTAssertEqual(try queue.jobs().count, 0)
        XCTAssertEqual(try library.contents().batches.count, 1)
    }
    func testIntakeFailureRetryAndPinnedLibrary() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary(), other = try intakeLibrary("Other")
        let target = intakeTarget(library), offline = temp.appendingPathComponent("Offline")
        try FileManager.default.moveItem(at: library.root, to: offline)
        XCTAssertThrowsError(try IntakeProcessor.process(job.id, in: queue, defaultTarget: target))
        let failed = try queue.jobs()[0]
        XCTAssertEqual(failed.state, "failed")
        XCTAssertEqual(failed.receipt!.target, target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.payload.path))
        XCTAssertThrowsError(try IntakeProcessor.retarget(job.id, in: queue, to: intakeTarget(other)))
        try FileManager.default.moveItem(at: offline, to: library.root)
        try queue.retry(job.id)
        _ = try IntakeProcessor.process(job.id, in: queue, defaultTarget: intakeTarget(other))
        XCTAssertEqual(try library.contents().batches.count, 1)
        XCTAssertEqual(try other.contents().batches.count, 0)
    }
    func testIntakeRetargetAndCommitProtection() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary(), other = try intakeLibrary("Other")
        var receipt = job.receipt!; receipt.target = intakeTarget(library)
        try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
        try IntakeProcessor.retarget(job.id, in: queue, to: intakeTarget(other))
        let updated = try queue.jobs()[0]
        _ = try other.importIntake(from: updated.payload, receipt: updated.receipt!)
        XCTAssertThrowsError(try IntakeProcessor.retarget(job.id, in: queue, to: intakeTarget(library)))
        _ = try IntakeProcessor.process(job.id, in: queue, defaultTarget: nil)
        XCTAssertEqual(try other.contents().batches.count, 1)
        XCTAssertEqual(try library.contents().batches.count, 0)
    }
    func testIntakePartialCancelAndLocks() throws {
        let queue = try IntakeQueue.create(at: temp.appendingPathComponent("Queue"))
        let draft = try queue.begin()
        try Data([1]).write(to: draft.payload.appendingPathComponent("part.txt"))
        XCTAssertEqual(try queue.jobs()[0].state, "incoming")
        XCTAssertThrowsError(try IntakeProcessor.process(draft.id, in: queue, defaultTarget: nil))
        XCTAssertThrowsError(try queue.discard(draft.id))
        try queue.withLock { XCTAssertThrowsError(try IntakeQueue(at: queue.root).withLock { }) }
        try queue.cancel(draft)
        XCTAssertEqual(try queue.jobs().count, 0)
    }
    func testIntakeDifferentSharesAndExternalInputPreserved() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        let draft = try queue.begin()
        for url in try FileManager.default.contentsOfDirectory(at: job.payload, includingPropertiesForKeys: nil) {
            try SafeFiles.copy(url, to: draft.payload.appendingPathComponent(url.lastPathComponent))
        }
        _ = try queue.publish(draft)
        let external = temp.appendingPathComponent("external.w2adrop")
        try SafeFiles.copy(job.payload, to: external)
        for pending in try queue.jobs() { _ = try IntakeProcessor.process(pending.id, in: queue, defaultTarget: intakeTarget(library)) }
        XCTAssertEqual(try library.contents().batches.count, 2)
        _ = try library.importData(from: external)
        XCTAssertEqual(try library.contents().batches.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.appendingPathComponent("Chat History.txt").path))
    }
    func testIntakeConflictPreservesBothCopies() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        var receipt = job.receipt!; receipt.target = intakeTarget(library)
        try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
        let batch = try library.importIntake(from: job.payload, receipt: receipt)
        try "changed".write(to: job.payload.appendingPathComponent("example.md"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try IntakeProcessor.process(job.id, in: queue, defaultTarget: nil))
        XCTAssertEqual(try queue.jobs()[0].state, "failed")
        XCTAssertEqual(try library.contents().batches.count, 1)
        XCTAssertEqual(try String(contentsOf: batch.workspace.appendingPathComponent("original/payload.w2adrop/example.md"), encoding: .utf8), "fixture only")
        XCTAssertNil(try queue.completion(job.id))
    }
    func testIntakeInvalidQueueAndSymlinks() throws {
        let (queue, job) = try intakeFixture()
        XCTAssertThrowsError(try IntakeIO.child("../outside", in: queue.root))
        let external = temp.appendingPathComponent("keep.txt")
        try "keep".write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: job.payload.appendingPathComponent("escape"), withDestinationURL: external)
        XCTAssertThrowsError(try IntakeIO.inventory(job.payload))
        let library = try intakeLibrary()
        XCTAssertThrowsError(try IntakeProcessor.process(job.id, in: queue, defaultTarget: intakeTarget(library)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        var dictionary = try JSONSerialization.jsonObject(with: Data(contentsOf: queue.root.appendingPathComponent("queue.json"))) as! [String: Any]
        dictionary["schemaVersion"] = 999
        try JSONSerialization.data(withJSONObject: dictionary).write(to: queue.root.appendingPathComponent("queue.json"))
        XCTAssertThrowsError(try IntakeQueue(at: queue.root))
    }
    func testIntakeCumulativeLimitsAndAbandonedPartial() throws {
        let queue = try IntakeQueue.create(at: temp.appendingPathComponent("Queue"))
        var draft: IntakeDraft? = try queue.begin()
        let id = draft!.id, payload = draft!.payload
        let first = payload.appendingPathComponent("01"), second = payload.appendingPathComponent("02")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        // Sparse input exceeds the aggregate size without allocating 512 MiB in the test fixture.
        for parent in [first, second] {
            let url = parent.appendingPathComponent("large.bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let f = try FileHandle(forWritingTo: url); try f.truncate(atOffset: UInt64(SafeFiles.byteLimit / 2 + 1)); try f.close()
        }
        XCTAssertThrowsError(try queue.publish(draft!))
        XCTAssertEqual(try queue.jobs()[0].state, "incoming")
        draft = nil // Simulate dead producer: flock must be released without touching the data.
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
        try queue.discard(id)
        XCTAssertTrue(try queue.jobs().isEmpty)
    }
}

extension WeChat2AICoreTests {
    func testIntakeStableNotificationAndMovedLibrary() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        let signal = try queue.signalURL()
        let metadata = try IntakeIO.read(IntakeQueueMetadata.self, at: signal.appendingPathComponent("queue-link.json"))
        XCTAssertEqual(metadata.queueID, queue.metadata.queueID)
        var receipt = job.receipt!; receipt.target = intakeTarget(library)
        try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
        let original = try library.importIntake(from: job.payload, receipt: receipt)
        let moved = temp.appendingPathComponent("MovedLibrary")
        try FileManager.default.moveItem(at: library.root, to: moved)
        let reopened = try LibraryStore.open(at: moved)
        try IntakeProcessor.retarget(job.id, in: queue, to: intakeTarget(reopened))
        let resumed = try IntakeProcessor.process(job.id, in: queue, defaultTarget: nil)
        XCTAssertEqual(resumed.completion.batchID, original.id)
        XCTAssertEqual(try reopened.contents().batches.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: signal.appendingPathComponent("queue-link.json").path))
        XCTAssertEqual(try queue.signalURL().path, signal.path)
        XCTAssertTrue(try queue.jobs().isEmpty)
    }
}

extension WeChat2AICoreTests {
    func testIntakeUnknownEntryDoesNotBlockValidJob() throws {
        let (queue, job) = try intakeFixture(), library = try intakeLibrary()
        let unknown = queue.root.appendingPathComponent("ready/user-notes.txt")
        try "preserve".write(to: unknown, atomically: true, encoding: .utf8)
        XCTAssertTrue(try queue.jobs().contains { $0.id == "user-notes.txt" && $0.issue != nil })
        _ = try IntakeProcessor.process(job.id, in: queue, defaultTarget: intakeTarget(library))
        XCTAssertEqual(try library.contents().batches.count, 1)
        XCTAssertThrowsError(try queue.discard("user-notes.txt"))
        XCTAssertEqual(try String(contentsOf: unknown, encoding: .utf8), "preserve")
    }
}
