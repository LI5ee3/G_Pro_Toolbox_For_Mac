import SwiftUI
import ToolboxDomain
import AppKit

/// A native choice row shared by the dense display, game and lighting pages.
struct ParameterPickerRow: View {
    let title: String
    let options: [Option]
    let selectedValue: Int
    let onSelect: (Int) -> Void

    private var selection: Int { options.contains { $0.value == selectedValue } ? selectedValue : -1 }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13, weight: .medium))
                .frame(width: Theme.parameterLabelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            ParameterPopUp(title: title, options: options, selection: selection, onSelect: onSelect)
                .frame(width: 220, height: 28)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }
}

/// Uses the native fixed-width popup already proven in the S3-01 proposal.
/// Updating a reading selects an item without sending a control action.
/// The unknown placeholder stays readable, and its tag never submits an action.
private struct ParameterPopUp: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let options: [Option]
    let selection: Int
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.controlSize = .regular
        view.font = .systemFont(ofSize: 13)
        view.autoenablesItems = false
        view.target = context.coordinator
        view.action = #selector(Coordinator.selected(_:))
        view.setAccessibilityLabel(title)
        return view
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        let titles = (selection == -1 ? ["未知"] : []) + options.map(\.label)
        let tags = (selection == -1 ? [-1] : []) + options.map(\.value)
        if view.itemTitles != titles || view.itemArray.map(\.tag) != tags {
            view.removeAllItems()
            for (title, tag) in zip(titles, tags) {
                view.addItem(withTitle: title)
                view.lastItem?.tag = tag
            }
        }
        view.selectItem(withTag: selection)
        view.isEnabled = isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 220, height: 28)
    }
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        init(_ onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }
        @objc func selected(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, item.isEnabled, item.tag != -1 else { return }
            onSelect(item.tag)
        }
    }
}
