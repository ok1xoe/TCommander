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
            btn("F3 Zobrazit") { model.view() }
            btn("F4 Editovat") { model.edit() }
            btn("F5 Kopírovat") { model.transfer(.copy) }
            btn("F6 Přesunout") { model.transfer(.move) }
            btn("F7 Nový adresář") { model.makeDirectory() }
            btn("F8 Smazat") { model.delete(permanent: false) }
        }
        .padding(2)
    }

    private func btn(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 11)).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.small)
    }
}
