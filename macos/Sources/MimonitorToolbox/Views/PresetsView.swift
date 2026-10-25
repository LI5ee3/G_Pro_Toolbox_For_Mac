import ToolboxDomain
import ToolboxApplication
import SwiftUI
import MimonitorPresetCore

struct PresetsView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PresetsModel.self) private var presets
    @State private var editor: PresetNameRequest?
    @State private var deleting: PicturePreset?
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("预设模式").font(.system(size: 22, weight: .semibold))
                    }
                    Spacer(minLength: 12)
                    Button {
                        editor = PresetNameRequest(preset: nil)
                    } label: {
                        Label("新建预设", systemImage: "plus")
                    }
                    .toolboxAction(prominent: true)
                    .controlSize(.regular)
                    .disabled(!connection.isConnected || presets.presetConfiguration.applicationIncomplete)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(presets.presetConfiguration.applicationIncomplete
                         ? "当前对象：\(state.activePresetName) · 应用未完成，自动保存已暂停"
                         : connection.isConnected
                         ? "当前对象：\(state.activePresetName)\(state.activePresetID == nil ? " · 仅调整显示器" : " · 画面调整自动保存到此预设")"
                         : "未连接时不自动保存画面调整。")
                    Label("菜单栏：\(presets.presetConfiguration.menuBarPresets.count)/4 个预设（含无预设）", systemImage: "menubar.rectangle")
                }
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                if !connection.isConnected {
                    Label("未连接显示器。可管理名称；创建、应用和编辑需先连接。", systemImage: "wifi.slash")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(spacing: 0) {
                    PresetRow(title: "无预设", summary: "不使用任何预设，仅修改当前显示器状态",
                               isCurrent: baselineIsCurrent, applicationIncomplete: false,
                               showInMenuBar: menuBarBinding(PicturePreset.baselineID),
                               canEnableMenuBar: presets.presetConfiguration.canEnableMenuBarPreset(id: PicturePreset.baselineID)) {
                        Button { state.restoreBaseline(edit: true); refreshImmediatePictureNavigation() } label: {
                            Text("编辑画面").frame(width: 64)
                        }
                        .toolboxAction()
                        .disabled(!connection.isConnected || (!baselineIsCurrent && !state.canRestoreBaseline))
                        Button { state.restoreBaseline() } label: {
                            Text("应用").frame(width: 48)
                        }
                        .toolboxAction()
                        .disabled(!state.canRestoreBaseline || baselineIsCurrent)
                    }
                    ForEach(presets.presetConfiguration.presets) { preset in
                        Divider().overlay(Theme.stroke.opacity(0.65)).padding(.horizontal, 18)
                        PresetRow(title: preset.name, summary: summary(preset),
                                   isCurrent: connection.isConnected && state.activePresetID == preset.id && !presets.presetConfiguration.applicationIncomplete,
                                   applicationIncomplete: state.activePresetID == preset.id && presets.presetConfiguration.applicationIncomplete,
                                   showInMenuBar: menuBarBinding(preset.id),
                                   canEnableMenuBar: presets.presetConfiguration.canEnableMenuBarPreset(id: preset.id)) {
                            Menu {
                                Button("重命名") { editor = PresetNameRequest(preset: preset) }
                                Button("删除…", role: .destructive) { deleting = preset; showDelete = true }
                            } label: {
                                Label("管理预设 \(preset.name)", systemImage: "ellipsis")
                                    .labelStyle(.iconOnly).frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .frame(width: 28, height: 28)
                            .background(Theme.control, in: RoundedRectangle(cornerRadius: 6))
                            .help("管理预设")
                            Button { state.applyPreset(id: preset.id, edit: true); refreshImmediatePictureNavigation() } label: {
                                Text("编辑画面").frame(width: 64)
                            }
                            .toolboxAction()
                            .disabled(!connection.isConnected)
                            Button { state.applyPreset(id: preset.id) } label: {
                                Text("应用").frame(width: 48)
                            }
                            .toolboxAction(prominent: state.activePresetID == preset.id && presets.presetConfiguration.applicationIncomplete)
                            .disabled(!connection.isConnected || (state.activePresetID == preset.id && !presets.presetConfiguration.applicationIncomplete))
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.sectionRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.sectionRadius).stroke(Theme.stroke.opacity(0.65)))

            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .font(.system(size: 14))
            .tint(Theme.accent)
            .disabled(presets.isPresetOperationInFlight)
        }
        .sheet(item: $editor) { request in
            PresetNameSheet(preset: request.preset) { name in
                if let preset = request.preset { state.renamePreset(id: preset.id, name: name) }
                else { state.createPreset(name: name) }
            }
        }
        .alert("删除预设？", isPresented: $showDelete, presenting: deleting) { preset in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { state.deletePreset(id: preset.id) }
        } message: { preset in
            Text("删除「\(preset.name)」及引用它的自动任务。正在使用时会先切回无预设；若它是任务结束后的返回目标，届时改回无预设。")
        }
    }

    private func refreshImmediatePictureNavigation() {
        // An already-active target navigates immediately, without the apply completion's refresh.
        if state.requestedPage == .picture { state.forceRefreshPage("picture") }
    }

    private var baselineIsCurrent: Bool {
        connection.isConnected && state.activePresetID == nil && !presets.presetConfiguration.applicationIncomplete
    }

    private func menuBarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { presets.presetConfiguration.normalizedMenuBarPresetIDs.contains(id) },
            set: { state.setPresetMenuBarVisibility(id: id, visible: $0) }
        )
    }

    private func summary(_ preset: PicturePreset) -> String {
        let mode = Int(preset.values["picture_mode"] ?? "") ?? -1
        let modeName = RegisterMap.sceneNames[mode] ?? (mode == -1 ? "模式未知" : "模式 \(mode)")
        let freesync = ["0": "关", "1": "开"][preset.values["freesync"] ?? ""] ?? "未知"
        return "\(modeName) · 背光 \(preset.values["picture_backlight"] ?? "—") · 对比度 \(preset.values["picture_contrast"] ?? "—") · FreeSync \(freesync)"
    }
}

/// Saved presets keep their status and actions beside the object they affect.
private struct PresetRow<Actions: View>: View {
    let title: String
    let summary: String
    let isCurrent: Bool
    let applicationIncomplete: Bool
    @Binding var showInMenuBar: Bool
    let canEnableMenuBar: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(isCurrent ? Theme.accent : Theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(isCurrent ? Theme.accent.opacity(0.10) : Theme.control,
                            in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Text(title).font(Theme.sectionFont).lineLimit(2)
                    if isCurrent {
                        Label("当前使用", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.accent).fixedSize()
                    } else if applicationIncomplete {
                        Label("应用未完成", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.warning).fixedSize()
                    }
                }
                Text(summary).font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) { actions }
                    .controlSize(.regular)
                Toggle("在菜单栏显示", isOn: $showInMenuBar)
                    .toggleStyle(.switch).controlSize(.small).fixedSize()
                    .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                    .disabled(!showInMenuBar && !canEnableMenuBar)
                    .help(canEnableMenuBar ? "将此预设加入菜单栏" : "菜单栏最多添加 4 个预设，请先关闭一个已有选项")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Theme.accent.opacity(0.035) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.sectionRadius))
    }
}

private struct PresetNameRequest: Identifiable {
    let id = UUID()
    let preset: PicturePreset?
}

private struct PresetNameSheet: View {
    @ToolboxActions private var state
    @Environment(PresetsModel.self) private var presets
    @Environment(\.dismiss) private var dismiss
    let preset: PicturePreset?
    let save: (String) -> Void
    @State private var name: String
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var nameFocused: Bool
    init(preset: PicturePreset?, save: @escaping (String) -> Void) {
        self.preset = preset; self.save = save
        _name = State(initialValue: preset?.name ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(preset == nil ? "新建预设" : "重命名预设", systemImage: "slider.horizontal.3")
                .font(.system(size: 22, weight: .semibold))
            if let preset { Text("当前对象：\(preset.name)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText) }
            VStack(alignment: .leading, spacing: 6) {
                Text("预设名称").font(.system(size: 13, weight: .medium))
                TextField("预设名称", text: $name).textFieldStyle(.roundedBorder)
                    .labelsHidden().disabled(saving).focused($nameFocused)
                    .accessibilityLabel("预设名称")
            }
            Text(preset == nil ? "读取当前设备设置后创建，并进入画面页继续调整。" : "重名时会自动添加序号；已有任务引用不受影响。")
                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
            if saving || presets.isPresetOperationInFlight {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(presets.presetOperationText) }
                    .font(.system(size: 13))
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13)).foregroundColor(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    .toolboxAction()
                    .disabled(saving)
                Button(saving ? "保存中…" : "保存") {
                    failure = nil
                    state.presetError = nil
                    saving = true
                    save(name)
                }
                    .toolboxAction(prominent: true)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || presets.isPresetOperationInFlight || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 460)
        .font(.system(size: 14))
        .tint(Theme.accent)
        .interactiveDismissDisabled(saving)
        .onChange(of: presets.isPresetOperationInFlight) { _, inFlight in
            guard saving, !inFlight else { return }
            saving = false
            if let message = presets.presetError {
                failure = message
                state.presetError = nil
                nameFocused = true
            } else {
                dismiss()
            }
        }
    }
}
