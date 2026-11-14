import Foundation
import WeChat2AICore

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    fputs("Usage: wechat2ai <ZIP, TXT, folder or .w2adrop> <output directory>\n", stderr)
    exit(2)
}
do {
    let result = try Importer.run(source: URL(fileURLWithPath: arguments[0]), inbox: URL(fileURLWithPath: arguments[1]))
    print("Workspace: \(result.workspace.path)")
    print("Messages: \(result.manifest.messageCount); participants: \(result.manifest.participants.count); attachments: \(result.manifest.linkedAttachmentCount)")
    for warning in result.manifest.warnings { print("Warning: \(warning)") }
} catch { fputs("Import failed: \(error.localizedDescription)\n", stderr); exit(1) }
