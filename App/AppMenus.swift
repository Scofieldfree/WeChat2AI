import AppKit

@MainActor
final class AppMenus: NSObject, NSMenuItemValidation {
    let model: AppModel
    init(model: AppModel) { self.model = model }
    func install() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); let menu = NSMenu(title: title); item.submenu = menu; bar.addItem(item); return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ key: String, _ shortcut: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: shortcut)
            item.representedObject = key; item.target = self; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        func native(_ menu: NSMenu, _ title: String, _ selector: String, _ shortcut: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: shortcut)
            item.keyEquivalentModifierMask = modifiers; item.tag = tag; menu.addItem(item)
        }
        let app = menu("WeChat2AI")
        native(app, "关于 WeChat2AI", "orderFrontStandardAboutPanel:")
        add(app, "设置…", "settings", ","); app.addItem(.separator())
        native(app, "隐藏 WeChat2AI", "hide:", "h"); native(app, "隐藏其他", "hideOtherApplications:", "h", [.command, .option])
        native(app, "全部显示", "unhideAllApplications:"); app.addItem(.separator()); native(app, "退出 WeChat2AI", "terminate:", "q")
        let file = menu("文件")
        add(file, "导入聊天记录…", "import", "o"); add(file, "待处理接收…", "intake")
        file.addItem(.separator()); add(file, "新建来源…", "newSource", "n"); add(file, "重命名来源…", "rename")
        file.addItem(.separator()); add(file, "打开资料库…", "openLibrary", "o", [.command, .shift]); add(file, "新建资料库…", "newLibrary")
        add(file, "在 Finder 中显示资料库", "libraryFinder"); file.addItem(.separator()); native(file, "关闭窗口", "performClose:", "w")
        let edit = menu("编辑")
        native(edit, "撤销", "undo:", "z"); native(edit, "重做", "redo:", "z", [.command, .shift]); edit.addItem(.separator())
        native(edit, "剪切", "cut:", "x"); native(edit, "拷贝", "copy:", "c"); native(edit, "粘贴", "paste:", "v"); native(edit, "全选", "selectAll:", "a")
        edit.addItem(.separator())
        native(edit, "查找…", "performTextFinderAction:", "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        native(edit, "查找下一个", "performTextFinderAction:", "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        native(edit, "查找上一个", "performTextFinderAction:", "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue)
        let view = menu("显示")
        add(view, "显示 / 隐藏来源侧栏", "sidebar", "s", [.command, .control]); add(view, "阅读视图", "reading", "1"); add(view, "原文视图", "source", "2"); add(view, "刷新资料库", "refresh", "r")
        let batch = menu("批次")
        add(batch, "归档到来源…", "assign"); add(batch, "本批资料与提醒…", "batchInfo", "i")
        add(batch, "在 Finder 中显示", "finder", "r", [.command, .shift]); add(batch, "查看项目目录", "project"); add(batch, "分享原件…", "share")
        let handoff = menu("交接")
        add(handoff, "交给 Codex", "agent", "\r"); add(handoff, "复制给 AI", "copy", "c", [.command, .shift])
        add(handoff, "编辑任务要求…", "task", "t"); add(handoff, "最近一次交接详情…", "handoffInfo")
        let window = menu("窗口")
        native(window, "最小化", "performMiniaturize:", "m"); native(window, "缩放", "performZoom:"); native(window, "前置全部窗口", "arrangeInFront:")
        NSApp.windowsMenu = window
        let help = menu("帮助"); add(help, "使用步骤", "usage"); add(help, "隐私与本地数据", "privacy"); NSApp.helpMenu = help
        NSApp.mainMenu = bar
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let key = item.representedObject as? String else { return true }
        if key == "assign" { item.title = model.assignmentTitle }
        if key == "agent" { item.title = "交给 " + model.selectedAgent.title }
        if ["settings", "usage", "privacy"].contains(key) { return model.interactionAvailable }
        guard NSApp.keyWindow === model.window else { return false }
        switch key {
        case "reading", "source": return model.canPerform("read")
        case "batchInfo": return model.canPerform("finder")
        default: return model.canPerform(key)
        }
    }
    @objc func invoke(_ item: NSMenuItem) {
        guard validateMenuItem(item), let key = item.representedObject as? String else { return }
        switch key {
        case "settings": model.showSettings()
        case "import": model.chooseImport()
        case "intake": model.showIntakeJobs()
        case "newSource": model.newSource()
        case "rename": model.renameSource()
        case "openLibrary": model.openLibrary()
        case "newLibrary": model.createLibrary()
        case "libraryFinder": model.revealLibrary()
        case "sidebar": model.toggleSidebar()
        case "reading": model.chooseTranscriptMode(.reading)
        case "source": model.chooseTranscriptMode(.source)
        case "refresh": model.refresh()
        case "assign": model.assignSelected()
        case "batchInfo": model.showBatchInfo()
        case "finder": model.reveal()
        case "project": model.revealProject()
        case "share": model.shareOriginal()
        case "agent": model.openInAgent()
        case "copy": model.copyContext()
        case "task": model.editTask()
        case "handoffInfo": model.showHandoff()
        case "usage": model.showUsageHelp()
        case "privacy": model.showPrivacyInfo()
        default: break
        }
    }
}
