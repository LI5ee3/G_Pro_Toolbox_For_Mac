package enum ControlStep {
    package static func alignToStep(_ value: Int, step: Int, increasing: Bool) -> Int {
        guard step > 1 else { return value + (increasing ? step : -step) }
        if value % step == 0 { return value + (increasing ? step : -step) }
        return increasing ? ((value / step) + 1) * step : (value / step) * step
    }

}
