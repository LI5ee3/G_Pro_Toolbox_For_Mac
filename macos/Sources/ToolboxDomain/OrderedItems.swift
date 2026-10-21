import Foundation

package enum OrderedItems {
    package static func move<T>(_ items: [T], from offsets: IndexSet, to destination: Int) -> [T] {
        let moved = offsets.map { items[$0] }
        var remaining = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: insertion)
        return remaining
    }
}
