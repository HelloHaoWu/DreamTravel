import SwiftUI

struct MobileReferenceLibraryView: View {
    @State private var entries: [ReferenceEntry] = []
    @State private var message = ""
    @State private var search = ""
    @State private var editing: ReferenceEntry?
    @State private var pendingDeletion: ReferenceEntry?
    private var filtered: [ReferenceEntry] {
        entries.filter { search.isEmpty || ($0.city + $0.idea.title + $0.idea.summary).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if !message.isEmpty { Text(message).foregroundStyle(.orange) }
            if entries.isEmpty {
                ContentUnavailableView("还没有旅行灵感", systemImage: "sparkles", description: Text("开启主动搜索后，安排一次行程就会积累有出处的新玩法。"))
            }
            ForEach(filtered) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.idea.title).font(.headline)
                        Spacer()
                        Toggle("用于后续安排", isOn: Binding(get: { entry.isEnabled }, set: { enabled in
                            var copy = entry; copy.isEnabled = enabled
                            Task { do { try await ReferenceLibrary.shared.update(copy); await reload() } catch { message = "保存失败，原设置保持不变。" } }
                        })).labelsHidden()
                    }
                    Text(entry.idea.summary).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(entry.city) · \(entry.savedAt.formatted(date: .abbreviated, time: .omitted)) · 搜索摘要参考")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("查看 \(entry.sources.count) 个出处") {
                        ForEach(entry.sources) { source in
                            if let url = ResearchURL.validated(source.url) { Link(source.title, destination: url).font(.caption) }
                        }
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) { pendingDeletion = entry }
                    Button("编辑") { editing = entry }.tint(.blue)
                }
            }
        }
        .navigationTitle("我的旅行灵感")
        .searchable(text: $search, prompt: "城市或玩法")
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("删除这条参考？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("删除", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                Task { do { try await ReferenceLibrary.shared.delete([entry.id]); pendingDeletion = nil; await reload() } catch { message = "删除失败，请重试。" } }
            }
        } message: { Text("后续不会再从资料库使用它，相同来源组合也不会自动重新入库。") }
        .sheet(item: $editing) { entry in
            ReferenceEditor(entry: entry) { updated in
                Task { do { try await ReferenceLibrary.shared.update(updated); editing = nil; await reload() } catch { message = "编辑保存失败，请重试。" } }
            }
        }
    }

    @MainActor private func reload() async {
        do { entries = try await ReferenceLibrary.shared.entries(); message = "" }
        catch { message = "参考库读取失败，原文件未被覆盖。" }
    }
}

private struct ReferenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ReferenceEntry
    let save: (ReferenceEntry) -> Void
    @State private var title = ""
    @State private var summary = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $title)
                TextField("参考意见", text: $summary, axis: .vertical).lineLimit(4...10)
                Text("只修改自己的参考意见，来源仍会保留。营业和价格不会因为编辑而变成已核实。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("编辑参考")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var copy = entry
                        copy.idea = DiscoveryIdea(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, searchTerms: entry.idea.searchTerms, sourceURLs: entry.idea.sourceURLs)
                        save(copy)
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary.isEmpty)
                }
            }
            .onAppear { title = entry.idea.title; summary = entry.idea.summary }
        }
    }
}
