import ToolboxDomain
import ToolboxApplication
import SwiftUI

/// 菜单栏快捷项与主窗口共用同一份设备状态及操作。
struct MenuBarSettingsView: View {
    @ToolboxActions var state
    @Environment(HotkeysModel.self) private var keyboard

    var body: some View {
        Form {
            Section {
                LabeledContent("快捷项", value: "\(keyboard.menuBarItems.count) 项")
                Button("恢复默认") { state.menuBarItems = MenuBarCatalog.defaultEnabled }
                    .toolboxAction()
                    .help("恢复默认快捷项及其排列顺序")
            } header: {
                Text("菜单栏配置")
            } footer: {
                Text("选择常用参数，菜单面板沿用这里的启用项与顺序。")
            }

            Section {
                if keyboard.menuBarItems.isEmpty {
                    ContentUnavailableView("尚未添加快捷项", systemImage: "menubar.rectangle",
                                           description: Text("在下方打开需要的项目。"))
                        .frame(maxWidth: .infinity)
                } else {
                    // Keep native drag reordering and the existing explicit move actions.
                    List {
                        ForEach(Array(keyboard.menuBarItems.enumerated()), id: \.element) { index, id in
                            if let entry = MenuBarCatalog.entry(id) {
                                HStack(spacing: 12) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(Theme.captionFont).foregroundStyle(Theme.secondaryText)
                                        .accessibilityHidden(true)
                                    Image(systemName: icon(for: entry))
                                        .foregroundStyle(Theme.accent).frame(width: 20)
                                    Text(entry.label)
                                    Spacer()
                                    Button { state.moveMenuBarItems(from: IndexSet(integer: index), to: index - 1) } label: {
                                        Image(systemName: "arrow.up")
                                    }
                                    .toolboxAction().disabled(index == 0)
                                    .accessibilityLabel("上移\(entry.label)")
                                    Button { state.moveMenuBarItems(from: IndexSet(integer: index), to: index + 2) } label: {
                                        Image(systemName: "arrow.down")
                                    }
                                    .toolboxAction().disabled(index == keyboard.menuBarItems.count - 1)
                                    .accessibilityLabel("下移\(entry.label)")
                                    Button { state.toggleMenuBarItem(id) } label: {
                                        Label("移除\(entry.label)", systemImage: "minus.circle")
                                            .labelStyle(.iconOnly)
                                    }
                                    .toolboxAction()
                                    .foregroundStyle(Theme.secondaryText)
                                    .help("从菜单栏移除\(entry.label)")
                                }
                                .listRowInsets(EdgeInsets(top: 5, leading: 4, bottom: 5, trailing: 4))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .onMove { from, to in state.moveMenuBarItems(from: from, to: to) }
                    }
                    .listStyle(.inset)
                    .environment(\.defaultMinListRowHeight, 44)
                    .frame(height: min(CGFloat(keyboard.menuBarItems.count) * 44 + 8, 228))
                }
            } header: {
                Text("快捷项顺序")
            } footer: {
                Text("拖动或使用上下移按钮调整顺序；修改立即保存，无需另点保存。")
            }

            Section {
                ForEach(MenuBarCatalog.all) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: icon(for: entry))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.label)
                            Text(describe(entry))
                                .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 12)
                        Toggle(entry.label, isOn: Binding(
                            get: { state.isMenuBarItemEnabled(entry.id) },
                            set: { enabled in
                                if enabled != state.isMenuBarItemEnabled(entry.id) {
                                    state.toggleMenuBarItem(entry.id)
                                }
                            }
                        ))
                        .labelsHidden().toggleStyle(.switch)
                    }
                }
            } header: {
                Text("选择快捷项")
            } footer: {
                Text("选项在菜单中显示为勾选列表；数值参数提供增大、减小操作。")
            }
        }
        .formStyle(.grouped)
    }

    private func icon(for entry: MenuBarEntry) -> String {
        switch entry.kind {
        case .options: return "checklist"
        case .stepper: return "slider.horizontal.3"
        }
    }

    private func describe(_ entry: MenuBarEntry) -> String {
        switch entry.kind {
        case .options(let opts):
            let names = opts.map(\.label)
            return names.count <= 4
                ? names.joined(separator: " / ")
                : "\(names.prefix(3).joined(separator: " / ")) 等 \(names.count) 项"
        case .stepper(let lo, let hi, let step):
            return "范围 \(lo)–\(hi) · 每次调节 \(step)"
        }
    }
}
