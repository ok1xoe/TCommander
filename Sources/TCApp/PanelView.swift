import AppKit
import SwiftUI
import TCCore

struct PanelView: View {
    @Bindable var model: AppModel
    let side: Side

    var body: some View {
        let group = model.group(side)
        let tab = group.active
        let isActive = model.activeSide == side
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                VolumeMenu { tab.navigate(to: $0); model.activeSide = side }
                TextField("Cesta", text: Binding(
                    get: { model.pathEdit[side.key] ?? tab.path.path },
                    set: { model.pathEdit[side.key] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { navigateToText(tab) }
                Button { tab.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
                Button { tab.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
                Button { tab.goUp() } label: { Image(systemName: "arrow.up") }
            }
            .buttonStyle(.borderless)
            .padding(6)
            TabBar(group: group, onSelect: { group.select($0); model.activeSide = side })
            FileTableView(
                tab: tab, revision: tab.revision, isActive: isActive,
                onFocus: { if model.activeSide != side { model.activeSide = side } },
                onKey: { model.handleKey($0, side: side) },
                onOpen: { model.activeSide = side; model.open() })
            StatusBar(tab: tab, message: tab.error)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(isActive ? Color.accentColor : .clear).frame(height: 2)
        }
        .onChange(of: tab.path) { _, _ in model.pathEdit[side.key] = nil }
        .onChange(of: group.activeIndex) { _, _ in model.pathEdit[side.key] = nil }
    }

    private func navigateToText(_ tab: PanelTab) {
        let p = ((model.pathEdit[side.key] ?? tab.path.path) as NSString).expandingTildeInPath
        tab.navigate(to: URL(fileURLWithPath: p))
        model.pathEdit[side.key] = nil
    }
}

struct TabBar: View {
    let group: PanelGroup
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(group.tabs.enumerated()), id: \.element.id) { i, t in
                    let title = t.path.path == "/" ? "/" : t.path.lastPathComponent
                    Text(title)
                        .lineLimit(1)
                        .font(.system(size: 11, weight: i == group.activeIndex ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(i == group.activeIndex ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(i) }
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 4)
        }
    }
}

struct StatusBar: View {
    let tab: PanelTab
    let message: String?

    var body: some View {
        let s = tab.summary
        HStack {
            if let message {
                Text(message).foregroundStyle(.red).lineLimit(1)
            } else if s.markedCount > 0 {
                Text("Označeno \(s.markedCount) z \(s.fileCount + s.dirCount) · \(Fmt.human(s.markedBytes))").foregroundStyle(.red)
            } else {
                Text("\(s.fileCount) souborů, \(s.dirCount) adresářů · \(Fmt.human(s.totalBytes))")
            }
            Spacer()
            Text(freeSpace())
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.bar)
    }

    private func freeSpace() -> String {
        guard let v = try? tab.path.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity else { return "" }
        return "\(Fmt.human(free)) volných z \(Fmt.human(Int64(total)))"
    }
}

struct VolumeMenu: View {
    let go: (URL) -> Void

    var body: some View {
        Menu {
            let home = FileManager.default.homeDirectoryForCurrentUser
            Button("Domů") { go(home) }
            ForEach(["Desktop", "Documents", "Downloads"], id: \.self) { n in
                Button(n) { go(home.appendingPathComponent(n)) }
            }
            Button("Aplikace") { go(URL(fileURLWithPath: "/Applications")) }
            Button("/") { go(URL(fileURLWithPath: "/")) }
            Divider()
            let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
            ForEach(vols, id: \.self) { v in
                Button((try? v.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? v.path) { go(v) }
            }
        } label: { Image(systemName: "externaldrive") }
        .menuStyle(.borderlessButton).fixedSize()
    }
}
