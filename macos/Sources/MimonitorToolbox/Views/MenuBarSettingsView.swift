import SwiftUI

/// 菜单栏快捷项与主窗口共用同一份设备状态及操作。
struct MenuBarSettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("菜单栏").font(.system(size: 23, weight: .semibold))
                        Text("不打开主窗口，也能调整常用参数。")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("恢复默认") { state.menuBarItems = MenuBarCatalog.defaultEnabled }
                        .toolboxAction()
                        .help("恢复默认快捷项及其排列顺序")
                }

                MenuSettingsSection(title: "快捷项顺序 · \(state.menuBarItems.count) 项") {
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow.and.square.on.square.dashed")
                            .foregroundStyle(Theme.accent)
                        Text("拖动下方条目调整顺序，修改立即保存。")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    if state.menuBarItems.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "menubar.rectangle")
                                .font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                            Text("尚未添加快捷项")
                            Text("在下方打开需要的项目。")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        // List + onMove 保留真正的原生拖放排序。
                        List {
                            ForEach(state.menuBarItems, id: \.self) { id in
                                if let entry = MenuBarCatalog.entry(id) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                            .accessibilityHidden(true)
                                        Image(systemName: icon(for: entry))
                                            .foregroundStyle(Theme.accent).frame(width: 20)
                                        Text(entry.label)
                                        Spacer()
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
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 44)
                        // 原生列表嵌套在页面滚动区时需要确定高度。
                        .frame(height: CGFloat(state.menuBarItems.count) * 44 + 8)
                    }
                }

                Divider()

                MenuSettingsSection(title: "选择快捷项") {
                    ForEach(MenuBarCatalog.all) { entry in
                        HStack(spacing: 14) {
                            Image(systemName: icon(for: entry))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 32, height: 32)
                                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.label)
                                Text(describe(entry))
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
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
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Label("选项在菜单中显示为勾选列表；数值参数提供增大、减小操作。", systemImage: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 14))
        .tint(Theme.accent)
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

private struct MenuSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
