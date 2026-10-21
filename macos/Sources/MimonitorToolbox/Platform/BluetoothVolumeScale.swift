import Foundation

/// CoreAudio scalar -> AVRCP's 0...127 integer -> the monitor's 0...100 integer.
/// macOS truncates the first conversion; this monitor rounds the second one.
/// Direct `volume / 100` therefore maps e.g. 10 to wire value 12 and display 9.
enum BluetoothVolumeScale {
    private static let wireMaximum = 127.0

    static func scalar(forVolume volume: Int) -> Float32 {
        let volume = min(max(volume, 0), 100)
        if volume == 0 { return 0 }
        if volume == 100 { return 1 }
        let wire = (Double(volume) * wireMaximum / 100).rounded()
        // Land just inside the desired truncation bucket, not on a Float32 boundary.
        return Float32((wire + 0.01) / wireMaximum)
    }

    /// Caller validates finite input in 0...1. Also decode values set outside ToolBox.
    static func volume(forScalar scalar: Float32) -> Int {
        // Tolerate Float32 representation of an exact incoming k/127 notification.
        let wire = min(max(floor(Double(scalar) * wireMaximum + 0.00001), 0), wireMaximum)
        return Int((wire * 100 / wireMaximum).rounded())
    }
}
