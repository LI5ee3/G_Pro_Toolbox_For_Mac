import ToolboxDomain
import ToolboxApplication
import SwiftUI
import MimonitorPresetCore

struct AutomaticTasksView: View {
    @ToolboxActions var state
    @Environment(PresetsModel.self) private var presets
    @State private var editing: ScheduledPresetTask?
    @State private var deleting: ScheduledPresetTask?
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自动任务").font(.system(size: 22, weight: .semibold))
                    }
                    Spacer(minLength: 12)
                    Button {
                        editing = ScheduledPresetTask(presetID: presets.presetConfiguration.presets.first?.id ?? PicturePreset.baselineID,
                                                       start: "18:00", end: "20:00")
                    } label: {
                        Label("新增任务", systemImage: "plus")
                    }
                    .toolboxAction(prominent: true)
                    .controlSize(.regular)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("每天按本地时间执行，结束后返回原预设的最新设置。支持跨午夜；重叠时靠下的任务优先。")
                    Label("应用需保持运行，关闭窗口驻留菜单栏也可执行。睡眠期间暂停，唤醒或重连后重新判断。", systemImage: "info.circle")
                }
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                if !presets.presetConfiguration.tasks.isEmpty || presets.presetConfiguration.session != nil {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").foregroundColor(Theme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(presets.automaticTaskStatus)
                                .font(.system(size: 13, weight: .medium))
                            if let session = presets.presetConfiguration.session {
                                let previous = presets.presetConfiguration.presets.first { $0.id == session.previousPresetID }?.name ?? "无预设"
                                Text("本轮结束后返回：\(previous)")
                                    .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.control.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
                if presets.presetConfiguration.tasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(Theme.accent)
                        Text("还没有自动任务").font(.system(size: 16, weight: .semibold))
                        Text("添加一个时段，自动切换到需要的预设。")
                            .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 38)
                }
                if !presets.presetConfiguration.tasks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(presets.presetConfiguration.tasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                Divider().overlay(Theme.stroke.opacity(0.65)).padding(.horizontal, 18)
                            }
                            taskRow(task, index: index)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.sectionRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.sectionRadius).stroke(Theme.stroke.opacity(0.65)))
                }

            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .font(.system(size: 14))
            .tint(Theme.accent)
            .disabled(presets.isPresetOperationInFlight)
        }
        .onAppear { state.checkAutomaticTasks() }
        .sheet(item: $editing) { task in
            AutomaticTaskSheet(task: task, presets: presets.presetConfiguration.presets) { state.saveAutomaticTask($0) }
        }
        .alert("删除自动任务？", isPresented: $showDelete, presenting: deleting) { task in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { state.deleteAutomaticTask(id: task.id) }
        } message: { _ in
            Text("若它正在生效，会重新判断剩余任务；没有其他命中任务时返回本轮开始前的预设。")
        }
    }
    private func taskRow(_ task: ScheduledPresetTask, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(verbatim: "\(task.start)–\(task.end)")
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(task.enabled ? .primary : Theme.secondaryText)
                Text((task.enabled ? "每天" : "已停用") + (isOvernight(task) ? " · 跨午夜" : ""))
                    .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                Spacer(minLength: 8)
                Toggle("启用", isOn: Binding(
                    get: { task.enabled },
                    set: { enabled in var updated = task; updated.enabled = enabled; state.saveAutomaticTask(updated) }
                ))
                .toggleStyle(.switch).controlSize(.small)
                .fixedSize()
                .font(.system(size: 13))
            }
            HStack(spacing: 10) {
                Label(presetName(task.presetID), systemImage: "display")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if presets.presetConfiguration.session?.taskID == task.id,
                   presets.presetConfiguration.session?.appliedTargetID == task.presetID {
                    Label("已执行", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(Theme.accent).fixedSize()
                }
                Spacer(minLength: 12)
                Text("优先级 \(index + 1)")
                    .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                    .fixedSize()
                    .help("重叠时靠下的任务优先")
                HStack(spacing: 5) {
                    Button { state.moveAutomaticTask(id: task.id, offset: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .toolboxAction()
                    .help("上移，降低重叠时的优先级")
                    .accessibilityLabel("上移任务")
                    .disabled(index == 0)
                    Button { state.moveAutomaticTask(id: task.id, offset: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .toolboxAction()
                    .help("下移，提高重叠时的优先级")
                    .accessibilityLabel("下移任务")
                    .disabled(index == presets.presetConfiguration.tasks.count - 1)
                }
                Button("编辑") { editing = task }.toolboxAction()
                Menu {
                    Button("删除…", role: .destructive) { deleting = task; showDelete = true }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("管理任务 \(task.start)–\(task.end)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetName(_ id: String) -> String {
        id == PicturePreset.baselineID ? "无预设" : presets.presetConfiguration.presets.first { $0.id == id }?.name ?? "预设已删除"
    }
    private func isOvernight(_ task: ScheduledPresetTask) -> Bool {
        guard let start = PresetSchedule.minute(task.start), let end = PresetSchedule.minute(task.end) else { return false }
        return start > end
    }
}

private struct AutomaticTaskSheet: View {
    @ToolboxActions private var state
    @Environment(PresetsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task: ScheduledPresetTask
    @State private var saving = false
    @State private var failure: String?
    let presets: [PicturePreset]
    let save: (ScheduledPresetTask) -> Void
    init(task: ScheduledPresetTask, presets: [PicturePreset], save: @escaping (ScheduledPresetTask) -> Void) {
        _task = State(initialValue: task); self.presets = presets; self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("自动任务", systemImage: "calendar.badge.clock")
                .font(.system(size: 22, weight: .semibold))
            Form {
                Picker("时段内使用", selection: $task.presetID) {
                    Text("无预设").tag(PicturePreset.baselineID)
                    ForEach(presets) { preset in Text(preset.name).tag(preset.id) }
                }
                DatePicker("开始时间", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                DatePicker("结束时间", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                Toggle("启用任务", isOn: $task.enabled)
            }
            .disabled(saving)
            Text("每天按所选时间执行，支持跨午夜，例如 23:00–02:00。开始时间包含在时段内，结束时间不包含；两者不能相同。")
                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
            if !task.isValid { Text("请填写有效且不同的开始、结束时间。") .font(.system(size: 13)).foregroundColor(Theme.warning) }
            if saving || model.isPresetOperationInFlight {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.presetOperationText) }
                    .font(.system(size: 13))
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    .toolboxAction().disabled(saving)
                Button(saving ? "保存中…" : "保存") {
                    failure = nil
                    state.presetError = nil
                    saving = true
                    save(task)
                }.keyboardShortcut(.defaultAction)
                    .toolboxAction(prominent: true)
                    .disabled(saving || model.isPresetOperationInFlight || !task.isValid)
            }
        }
        .padding(24).frame(width: 480)
        .font(.system(size: 14))
        .tint(Theme.accent)
        .interactiveDismissDisabled(saving)
        .onChange(of: model.isPresetOperationInFlight) { _, inFlight in
            guard saving, !inFlight else { return }
            saving = false
            if let message = model.presetError {
                failure = message
                state.presetError = nil
            } else if model.presetConfiguration.tasks.contains(task) {
                dismiss()
            } else {
                failure = "保存未完成，输入已保留，请重试。"
            }
        }
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: { PresetSchedule.timeDate(start ? task.start : task.end) ?? Date() },
            set: { date in
                let text = PresetSchedule.timeText(date)
                if start { task.start = text } else { task.end = text }
            }
        )
    }
}
