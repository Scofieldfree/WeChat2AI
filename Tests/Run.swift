import Foundation

private var failures = 0
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try left() != right() { fail("Values differ", file, line) } } catch { fail(error.localizedDescription, file, line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("Expected true", file, line) } } catch { fail(error.localizedDescription, file, line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try !value(), file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value == nil, file: file, line: line) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected error", file, line) } catch {}
}
private func fail(_ message: String, _ file: StaticString, _ line: UInt) { failures += 1; print("FAIL \(file):\(line): \(message)") }

@main struct TestRunner {
    static func main() throws {
        let suite = WeChat2AICoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("English/Chinese headers and multiline", suite.testEnglishAndChineseDatesAndMultiline),
            ("English media and emoji", suite.testEnglishMediaAndEmoji),
            ("Raw fallback and invalid dates", suite.testRawFallbackAndInvalidDate),
            ("Unparsed prefix and timestamp in body", suite.testPrefixPreservedAndTimestampLikeBody),
            ("Folder import and media integrity", suite.testImportLinksMediaAndPreservesOriginal),
            ("Deflated ZIP round trip", suite.testDeflatedZIPRoundTrip),
            ("Atomic failure cleanup", suite.testFailedImportLeavesNoPartialWorkspace),
            ("Missing and ambiguous media", suite.testMissingAndAmbiguousAttachments),
            ("Symlink rejected", suite.testSymlinkRejected),
            ("ZIP traversal, symlink and CRC rejected", suite.testZIPTraversalSymlinkAndCRCRejected),
            ("Stored ZIP and truncation", suite.testStoredZIPAndTruncation),
            ("Share package round trip", suite.testSharePackageRoundTrip),
            ("Codex path encoding and prefill-only contract", suite.testCodexURLPreservesSpecialPathAndOnlyPrefills),
            ("Codex missing workspace rejection", suite.testCodexMissingWorkspaceFails),
            ("Codex action prompts and raw intent", suite.testCodexActionsUseWorkspaceAndPreserveRawIntent),
            ("Library grouping, duplicate names and rename", suite.testLibraryGroupingAndNames),
            ("Archive integrity and failed reassignment", suite.testArchivePreservesFilesAndFailure),
            ("Unavailable library and unknown versions", suite.testLibraryUnavailableAndUnknownVersion),
            ("Corrupt records and symlink rejection", suite.testCorruptBatchIsReportedAndSymlinkRejected),
            ("Library writer exclusion", suite.testLibraryWriterExclusion),
            ("Recovery before and after move", suite.testRecoveryBeforeAndAfterMove),
            ("Recovery conflicts and traversal", suite.testRecoveryConflictAndTraversalPreserveFiles),
            ("Interrupted import and cleanup", suite.testInterruptedImportRecoveryAndFailedImportCleanup),
            ("Independent scoped handoff", suite.testHandoffIndependentAndScoped),
            ("Failed handoff has no partial output", suite.testHandoffFailureLeavesNoPartialPackage),
            ("Source time precision and old schema", suite.testSourceTimestampPrecision),
            ("Intake round trip and duplicate notification", suite.testIntakeRoundTripAndDuplicateNotification),
            ("Intake crash after commit and archive", suite.testIntakeCrashAfterCommitAndArchive),
            ("Intake acknowledged cleanup resumes", suite.testIntakeAcknowledgedCleanupCanResume),
            ("Intake failure retry and pinned library", suite.testIntakeFailureRetryAndPinnedLibrary),
            ("Intake retarget and commit protection", suite.testIntakeRetargetAndCommitProtection),
            ("Intake partial cancellation and locks", suite.testIntakePartialCancelAndLocks),
            ("Intake repeated shares and external preservation", suite.testIntakeDifferentSharesAndExternalInputPreserved),
            ("Intake conflict preserves copies", suite.testIntakeConflictPreservesBothCopies),
            ("Intake invalid queue and symlink rejection", suite.testIntakeInvalidQueueAndSymlinks),
            ("Intake cumulative limit and abandoned partial", suite.testIntakeCumulativeLimitsAndAbandonedPartial),
            ("Intake stable notification and moved library", suite.testIntakeStableNotificationAndMovedLibrary),
            ("Intake unknown entry does not block valid job", suite.testIntakeUnknownEntryDoesNotBlockValidJob),
            ("Managed project reuses workspace and scopes batches", suite.testManagedProjectReusesWorkspaceAndScopesEachBatch),
            ("Managed project rename and reassignment", suite.testManagedProjectRenameAndReassignmentPreserveHistory),
            ("Managed project group and library isolation", suite.testManagedProjectSeparatesSameNamesAndLibraries),
            ("Managed project missing, version and symlink protection", suite.testManagedProjectMissingOrInvalidDoesNotReplaceFiles),
            ("Managed project binding recovery and traversal protection", suite.testManagedProjectRecoversBindingAfterRenameAndRejectsTraversal),
            ("Unfiled fallback and project URL mismatch", suite.testUnfiledHandoffAndProjectURLMismatch),
            ("Analysis snapshots only selected history", suite.testAnalysisComparisonSnapshotsOnlySelectedSameGroup),
            ("Analysis rejects invalid scope and cleans up", suite.testAnalysisRejectsEmptyForeignDuplicateContextAndCleansUp),
            ("Analysis snapshots selected results without writes", suite.testAnalysisConclusionSelectedResultsAreSnapshotsAndReadOnly),
            ("Analysis rejects escaped and oversized result files", suite.testAnalysisResultEscapeAndLargeInputsAreRejected),
            ("Template removal clears only its default references", suite.testTemplateRemovalClearsOnlyItsDefaults),
            ("Task templates defaults and corruption protection", suite.testTaskTemplatesDefaultsAndCorruptionProtection),
            ("Custom, requirements and raw task contracts", suite.testTaskCustomRequirementsAndRawHandoffContracts),
            ("Desktop agents share group and preserve context", suite.testDesktopAgentsShareGroupProjectAndImmutableContext),
            ("Claude URL encoding and unfiled fallback", suite.testClaudeURLRoundTripAndUnfiledFallback),
            ("Claude long task and strict manifest validation", suite.testClaudeLongTaskUsesCompleteManifestAndRejectsUnknownVersion),
            ("Desktop unavailable and failed handoff preservation", suite.testDesktopMissingAppCreatesNothingAndLinkFailurePreservesSnapshot),
            ("Agent preferences and task independence", suite.testAgentPreferenceAndAllTaskPromptsRemainIndependent),
            ("Cowork shared folder and relative scope", suite.testCoworkUsesSharedFolderAndRelativeScope),
            ("Cowork unfiled, long task and manifest failure", suite.testCoworkUnfiledLongTaskAndManifestFailure),
            ("Three independent Agent picker options", suite.testThreeIndependentAgentPickerOptions),
            ("testAgentWorkspaceDefaultsAndIndependentHandoff", suite.testAgentWorkspaceDefaultsAndIndependentHandoff),
        ]
        for (name, test) in tests {
            let before = failures
            try suite.setUpWithError()
            do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
            try suite.tearDownWithError()
            if failures == before { print("PASS \(name)") }
        }
        print("\(tests.count) tests; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
