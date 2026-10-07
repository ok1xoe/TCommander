import SwiftUI
import TCCore

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                PanelView(model: model, side: .left).frame(minWidth: 380)
                PanelView(model: model, side: .right).frame(minWidth: 380)
            }
            JobsBar(jobs: model.jobs)
            CommandLineBar(model: model)
            FKeyBar(model: model)
        }
        .frame(minWidth: 900, minHeight: 520)
        .overlay(alignment: .bottomTrailing) {
            if let busy = model.busy {
                HStack { ProgressView().controlSize(.small); Text(busy) }
                    .padding(8).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 8)).padding(40)
            }
        }
    }
}

struct CommandLineBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text(model.source.path.path + " ›").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            TextField("příkaz (Enter spustí, „cd cesta“ změní adresář)", text: $model.commandLine)
                .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                .onSubmit { model.runCommandLine() }
                .onKeyPress(.upArrow) { model.historyPrevious(); return .handled }
                .onKeyPress(.downArrow) { model.historyNext(); return .handled }
            if let s = model.status { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.bar)
    }
}

struct FKeyBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 1) {
            btn("F2 Přejmenovat") { model.rename() }
            btn("⌃M Hromadně") { model.multiRename() }
            btn("F3 Zobrazit") { model.view() }
            btn("F4 Editovat") { model.edit() }
            btn("F5 Kopírovat") { model.transfer(.copy) }
            btn("F6 Přesunout") { model.transfer(.move) }
            btn("F7 Nový adresář") { model.makeDirectory() }
            btn("⌥F7 Hledat") { model.search() }
            btn("F8 Smazat") { model.delete(permanent: false) }
        }
        .padding(2)
    }

    private func btn(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 11)).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.small)
    }
}

struct JobsBar: View {
    let jobs: JobManager

    var body: some View {
        if !jobs.jobs.isEmpty {
            VStack(spacing: 4) {
                ForEach(jobs.jobs) { job in
                    HStack(spacing: 8) {
                        Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 260, alignment: .leading)
                        ProgressView(value: job.progress.fraction).frame(maxWidth: 260)
                        Text(job.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if job.state != .queued {
                            Button { jobs.togglePause(job) } label: { Image(systemName: job.state == .paused ? "play.fill" : "pause.fill") }
                        }
                        Button { jobs.cancel(job) } label: { Image(systemName: "xmark") }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.bar)
        }
    }
}
