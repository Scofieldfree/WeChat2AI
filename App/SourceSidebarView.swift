import SwiftUI
import UniformTypeIdentifiers

struct SourceSidebarView: View {
    @ObservedObject var model: AppModel
    @StateObject private var keyboard = ListKeyboardTarget()
    @State private var dropTarget: String?
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        section("收件")
                        ForEach(model.sourceOptions.filter { $0.1 == "unfiled" }, id: \.1) { title, id in row(title, id) }
                        section("群与对话")
                        ForEach(model.contents.sources, id: \.id) { source in row(model.sourceName(source), source.id) }
                    }.padding(.horizontal, 8).padding(.vertical, 8)
                }.onChange(of: model.selectedSource) { id in proxy.scrollTo(id, anchor: .center) }
            }.accessibilityLabel("来源列表")
            W2ADivider()
            HStack { Button { model.newSource() } label: { Label("新建来源", systemImage: "plus") }; Spacer() }
                .padding(.horizontal, 12).frame(height: 44).disabled(!model.canPerform("newSource"))
        }.background(Color.w2aSidebar)
            .background(ListKeyboardAnchor(target: keyboard, move: move).frame(width: 0, height: 0))
    }
    private func section(_ title: String) -> some View {
        Text(title).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }
    private func row(_ title: String, _ id: String) -> some View {
        let source = model.contents.sources.first { $0.id == id }
        let selected = model.selectedSource == id
        let count = model.sourceCounts[id] ?? 0
        return Button { keyboard.focus(); model.selectSource(id) } label: {
            HStack(spacing: 8) {
                Image(systemName: id == "unfiled" ? "tray" : source?.kind == "direct" ? "person" : "person.2").frame(width: 18).accessibilityHidden(true)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                    Text("\(count)").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(id == "unfiled" && count > 0 ? Color(nsColor: W2ATheme.Colors.accentSoft) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }.font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aText).padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
                .background(selected ? Color(nsColor: W2ATheme.Colors.selected) : dropTarget == id ? Color(nsColor: W2ATheme.Colors.accentSoft) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) { if selected { RoundedRectangle(cornerRadius: 2).fill(Color.w2aAccent).frame(width: 3).padding(.vertical, 5) } }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(keyboard.hasFocus && selected ? Color.w2aAccent : .clear, lineWidth: 2))
        }.buttonStyle(.plain).id(id).disabled(!model.interactionAvailable)
            .help(source?.label ?? title).accessibilityElement(children: .ignore)
            .accessibilityLabel(title + (source?.note.isEmpty == false ? "，" + source!.note : "") + "，\(count) 个导入批次")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .contextMenu { if let source { Button("重命名来源…") { model.renameSource(id: source.id) }.disabled(!model.canPerform("newSource")) } }
            .onDrop(of: [UTType.plainText], isTargeted: Binding(get: { dropTarget == id }, set: { dropTarget = $0 ? id : nil })) { providers in
                guard model.interactionAvailable, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value else { return }
                    DispatchQueue.main.async { _ = model.assignDropped(value, to: id) }
                }
                return true
            }
    }
    private func move(_ direction: MoveCommandDirection) {
        guard model.interactionAvailable, direction == .up || direction == .down else { return }
        let ids = model.sourceOptions.map(\.1), current = model.sourceOptions.firstIndex { $0.1 == model.selectedSource } ?? 0
        let index = max(0, min(ids.count - 1, current + (direction == .down ? 1 : -1)))
        guard ids.indices.contains(index) else { return }
        model.selectSource(ids[index])
    }
}
