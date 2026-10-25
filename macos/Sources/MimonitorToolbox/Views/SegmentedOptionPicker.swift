import AppKit
import SwiftUI
import ToolboxDomain

// Reused from YiHoooong/Mimonitor_Toolbox, Views/Components.swift (upstream 56fa67e8d990a2dd8d7ebe1b6865d3b18928d08d).
// A fixed-width native control keeps the two app preference rows aligned.
struct SegmentedOptionPicker: NSViewRepresentable {
    let options: [Option]
    let selectedValue: Int
    /// 选项组用等宽；设置页的两段式控件用按内容分配，长标签才不会被截断。
    var distribution: NSSegmentedControl.Distribution = .fillEqually
    var controlSize: NSControl.ControlSize = .large
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.label),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = distribution
        control.controlSize = controlSize
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateSelection(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.segmentDistribution = distribution
        control.controlSize = controlSize
        if control.segmentCount != options.count {
            control.segmentCount = options.count
        }
        for (index, option) in options.enumerated()
        where control.label(forSegment: index) != option.label {
            control.setLabel(option.label, forSegment: index)
        }
        updateSelection(control)
    }

    private func updateSelection(_ control: NSSegmentedControl) {
        control.selectedSegment = options.firstIndex { $0.value == selectedValue } ?? -1
    }

    final class Coordinator: NSObject {
        var parent: SegmentedOptionPicker

        init(_ parent: SegmentedOptionPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < parent.options.count else { return }
            parent.onSelect(parent.options[index].value)
        }
    }
}
