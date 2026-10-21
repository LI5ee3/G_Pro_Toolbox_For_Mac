import Foundation

/// Shared firmware values. UI labels and preset write plans keep their existing order and semantics.
package enum PictureMappings {
    package static let colorTempToMtk = [0: 1, 1: 2, 2: 3, 3: 0, 4: 4, 5: 5, 8: 6]
    package static let mtkToColorTemp = [1: 0, 2: 1, 3: 2, 0: 3, 4: 4, 5: 5, 6: 8]
    package static let hdrToneMappingToMtk = [0: 5, 1: 0, 2: 2, 3: 1]
    package static let hdrToneMappingToUI = [5: 0, 0: 1, 2: 2, 1: 3]
    package static let hdrModes: Set<Int> = [11, 12, 13, 15, 16, 17, 18, 19, 22, 23,
                                           29, 30, 31, 32, 33, 39, 40, 41, 42, 43, 44]
}

package enum ControlRanges {
    package static let backlight = 1...100
    package static let percentage = 0...100
    package static let colorGain = 524...1524
    // The panel is one-based; the firmware is zero-based. Do not merge these ranges.
    package static let screenLightUI = 1...15
    package static let screenLightDevice = 0...14
}
