import Foundation

package struct AudioOutputSnapshot: Sendable, Equatable {
    package let uid: String
    package let name: String
    package init(uid: String, name: String) { self.uid = uid; self.name = name }
}
