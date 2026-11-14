import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let idealSidebar = min(W2ATheme.Layout.sidebarMax, max(W2ATheme.Layout.sidebarMin, geometry.size.width * 0.1864))
            let idealBatch = min(W2ATheme.Layout.batchMax, max(W2ATheme.Layout.batchMin, geometry.size.width * 0.2373))
            let shortage = max(0, W2ATheme.Layout.readingMinimum + idealSidebar + idealBatch + 2 - geometry.size.width)
            let sidebarWidth = max(W2ATheme.Layout.sidebarMin, idealSidebar - shortage)
            let batchWidth = max(W2ATheme.Layout.batchMin, idealBatch - max(0, shortage - (idealSidebar - sidebarWidth)))
            let canShowSidebar = geometry.size.width - sidebarWidth - batchWidth - 2 >= W2ATheme.Layout.readingMinimum
            let sidebarVisible = canShowSidebar && !model.sidebarCollapsed
            let readingWidth = geometry.size.width - batchWidth - 1 - (sidebarVisible ? sidebarWidth + 1 : 0)
            VStack(spacing: 0) {
                toolbar(sidebarVisible: sidebarVisible, width: geometry.size.width)
                W2ADivider()
                HStack(spacing: 0) {
                    if sidebarVisible { SourceSidebarView(model: model).frame(width: sidebarWidth); W2ADivider(vertical: true) }
                    BatchListView(model: model).frame(width: batchWidth)
                    W2ADivider(vertical: true)
                    BatchDetailView(model: model, availableWidth: readingWidth).frame(width: readingWidth)
                }.frame(maxHeight: .infinity)
                W2ADivider()
                HStack(spacing: 8) {
                    W2AStatus(message: model.statusMessage, tone: model.busy || model.previewLoading ? .working : model.statusTone, compact: true)
                    Button("详情") { model.showStatus() }.buttonStyle(W2ALinkButtonStyle()).disabled(!model.interactionAvailable)
                }.padding(.horizontal, 16).frame(height: W2ATheme.Layout.status).background(Color.w2aSurface)
            }.onAppear { model.sidebarCanShow = canShowSidebar }
                .onChange(of: canShowSidebar) { model.sidebarCanShow = $0 }
        }.frame(minWidth: W2ATheme.Layout.minimum.width, minHeight: W2ATheme.Layout.minimum.height)
            .font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aText).background(Color.w2aCanvas)
            .tint(Color.w2aAccent).accentColor(Color.w2aAccent).buttonStyle(W2AButtonStyle(compact: true))
    }
    private func toolbar(sidebarVisible: Bool, width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left").frame(width: 20) }
                .accessibilityLabel(sidebarVisible ? "收起来源侧栏" : "打开来源列表")
                .popover(isPresented: $model.sourcePopoverVisible) {
                    SourceSidebarView(model: model).frame(width: 220, height: 430).buttonStyle(W2AButtonStyle(compact: true)).tint(Color.w2aAccent)
                }.onChange(of: model.selectedSource) { _ in model.sourcePopoverVisible = false }
            if width >= 1040 { W2ABrandView().frame(width: 118, height: 28).accessibilityLabel("WeChat2AI") }
            Menu {
                Button("完整路径与信息…") { model.showLibraryInfo() }
                Button("打开其他资料库…") { model.openLibrary() }
                Button("新建资料库…") { model.createLibrary() }
                Button("在 Finder 中显示") { model.revealLibrary() }.disabled(!model.canPerform("libraryFinder"))
                Button("刷新资料库") { model.refresh() }
            } label: {
                HStack(spacing: W2ATheme.Space.sm) {
                    Text(model.libraryDisplayName).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
                }
            }
                .menuIndicator(.hidden)
                .frame(maxWidth: 160, alignment: .leading).disabled(!model.interactionAvailable)
                .accessibilityLabel("资料库管理与切换：" + model.libraryDisplayName)
                .help("切换、新建资料库或查看当前资料库信息")
            if !sidebarVisible {
                Picker("来源", selection: Binding(get: { model.selectedSource }, set: { model.selectSource($0) })) {
                    ForEach(model.sourceOptions, id: \.1) { name, id in Text(name).tag(id) }
                }.labelsHidden().frame(width: 145).disabled(!model.interactionAvailable).accessibilityLabel("当前来源")
            }
            Spacer(minLength: 8)
            if model.intakeCount > 0 || model.intakeHasErrors {
                Button { model.showIntakeJobs() } label: {
                    Label("待处理接收 \(model.intakeCount)", systemImage: model.intakeHasErrors || model.intakeHasFailures ? "exclamationmark.triangle" : "tray.and.arrow.down")
                }.disabled(!model.interactionAvailable)
            }
            Button { model.showSettings() } label: { Label("设置", systemImage: "gearshape") }
                .fixedSize().disabled(!model.interactionAvailable).accessibilityLabel("应用设置")
                .help("通用、资料库与数据、接收、任务与 Agent（⌘,）")
            Button { model.chooseImport() } label: { Label("导入聊天记录", systemImage: "square.and.arrow.down") }.disabled(!model.canPerform("import"))
        }.padding(.horizontal, 16).frame(height: W2ATheme.Layout.toolbar).background(Color.w2aSurface)
    }
}

struct W2ABrandView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let url = Bundle.main.url(forResource: scheme == .dark ? "wordmark-dark" : "wordmark-light", withExtension: "svg"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else { Text("WeChat2AI").font(W2ATheme.TypeStyle.title) }
    }
}
