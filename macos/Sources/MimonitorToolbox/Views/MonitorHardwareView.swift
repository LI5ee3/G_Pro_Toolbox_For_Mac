import SwiftUI

/// The physical monitor, with caller-supplied content clipped to its 16:9 panel.
/// All hardware coordinates use a 1000 × 835 canvas; its size follows the parent.
struct MonitorHardwareView<Screen: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let screen: Screen

    private var isDark: Bool { colorScheme == .dark }

    private func hardwareBlack(_ light: Double, dark: Double) -> Color {
        Color(white: isDark ? dark : light)
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1000, geometry.size.height / 835)

            ZStack(alignment: .topLeading) {
                // A narrow contact shadow keeps the base grounded without a halo.
                Ellipse()
                    .fill(Color.black.opacity(0.15))
                    .blur(radius: 3 * scale)
                    .hardwareRegion(CGRect(x: 327, y: 818, width: 346, height: 10), scale: scale)

                stand(scale: scale)
                base(scale: scale)
                panel(scale: scale)
            }
            .frame(width: 1000 * scale, height: 835 * scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1.20, contentMode: .fit)
    }

    private func panel(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Rear shell, fine edge highlight, and black front bezel are distinct.
            RoundedRectangle(cornerRadius: 3.5 * scale)
                .fill(Color(white: 0.035))
                .shadow(color: .black.opacity(0.16), radius: 2 * scale, x: 0, y: 2 * scale)
                .hardwareRegion(CGRect(x: 19, y: 13, width: 962, height: 564), scale: scale)

            RoundedRectangle(cornerRadius: 3 * scale)
                .fill(LinearGradient(
                    colors: [Color(white: 0.28), Color(white: 0.12), Color(white: 0.055)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .hardwareRegion(CGRect(x: 20, y: 14, width: 960, height: 561), scale: scale)

            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color(white: 0.018))
                .hardwareRegion(CGRect(x: 21.5, y: 16, width: 957, height: 557), scale: scale)

            // 952 / 535.5 = 16 / 9. No glass tint is applied over the content.
            screen
                .frame(width: 952 * scale, height: 535.5 * scale)
                .clipped()
                .position(x: 500 * scale, y: 286.75 * scale)

            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.105), Color(white: 0.055), Color(white: 0.025)],
                    startPoint: .top, endPoint: .bottom
                ))
                .hardwareRegion(CGRect(x: 23, y: 554.5, width: 954, height: 17), scale: scale)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .hardwareRegion(CGRect(x: 24, y: 553.5, width: 952, height: 0.75), scale: scale)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .hardwareRegion(CGRect(x: 25, y: 570.5, width: 950, height: 0.7), scale: scale)

            // Small dark manufacturer mark on the chin, without promotional art.
            HStack(spacing: 1.2 * scale) {
                RoundedRectangle(cornerRadius: 0.6 * scale)
                    .fill(Color(white: 0.38))
                    .frame(width: 2.5 * scale, height: 3.5 * scale)
                Rectangle()
                    .fill(Color(white: 0.29))
                    .frame(width: 13 * scale, height: 1.3 * scale)
            }
            .position(x: 44 * scale, y: 562 * scale)
        }
        .frame(width: 1000 * scale, height: 835 * scale)
    }

    private func stand(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: hardwareBlack(0.23, dark: 0.32), location: 0),
                        .init(color: hardwareBlack(0.125, dark: 0.235), location: 0.16),
                        .init(color: hardwareBlack(0.085, dark: 0.185), location: 0.48),
                        .init(color: hardwareBlack(0.025, dark: 0.115), location: 0.93),
                        .init(color: hardwareBlack(0.10, dark: 0.245), location: 1)
                    ], startPoint: .leading, endPoint: .trailing
                ))
                .hardwareRegion(CGRect(x: 463, y: 570, width: 74, height: 231), scale: scale)

            MonitorHardwareFacet(.standLeft)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.13 : 0.09), Color.white.opacity(0.015)],
                    startPoint: .leading, endPoint: .trailing
                ))

            MonitorHardwareFacet(.standRight)
                .fill(Color.black.opacity(isDark ? 0.16 : 0.34))

            // The aperture's bevel is an annulus, never a filled background patch.
            MonitorCableBevel()
                .fill(LinearGradient(
                    colors: [
                        isDark ? Color(white: 0.20) : Color.black.opacity(0.9),
                        hardwareBlack(0.23, dark: 0.43),
                        hardwareBlack(0.11, dark: 0.29)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), style: FillStyle(eoFill: true))

            Rectangle()
                .fill(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
                .hardwareRegion(CGRect(x: 463, y: 575, width: 74, height: 19), scale: scale)

            if isDark {
                // A restrained rim describes the black silhouette at small sizes.
                // It is cut by the same mask, so the aperture stays transparent.
                MonitorStandCutout()
                    .stroke(Color.white.opacity(0.16), lineWidth: max(0.65, 1.15 * scale))
            }
        }
        .frame(width: 1000 * scale, height: 835 * scale)
        // Cut every material layer together so both light and dark backgrounds show through.
        .mask(MonitorStandCutout().fill(style: FillStyle(eoFill: true)))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5 * scale)
                .fill(hardwareBlack(0.045, dark: 0.15))
                .hardwareRegion(CGRect(x: 446, y: 574, width: 108, height: 6), scale: scale)
        }
    }

    private func base(scale: CGFloat) -> some View {
        ZStack {
            MonitorHardwareFacet(.baseShell)
                .fill(hardwareBlack(0.035, dark: 0.115))
            MonitorHardwareFacet(.baseTop)
                .fill(LinearGradient(
                    colors: [
                        hardwareBlack(0.16, dark: 0.245),
                        hardwareBlack(0.10, dark: 0.20),
                        hardwareBlack(0.065, dark: 0.155)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
            MonitorHardwareFacet(.baseLeft)
                .fill(hardwareBlack(0.115, dark: 0.225))
            MonitorHardwareFacet(.baseRight)
                .fill(hardwareBlack(0.075, dark: 0.17))
            MonitorHardwareFacet(.baseFront)
                .fill(LinearGradient(
                    colors: [hardwareBlack(0.17, dark: 0.285), hardwareBlack(0.045, dark: 0.15)],
                    startPoint: .top, endPoint: .bottom
                ))
            MonitorHardwareFacet(.baseRidge)
                .stroke(Color.white.opacity(isDark ? 0.20 : 0.10), lineWidth: isDark ? max(0.65, 1.1 * scale) : 0.8 * scale)

            if isDark {
                MonitorHardwareFacet(.baseShell)
                    .stroke(Color.white.opacity(0.15), lineWidth: max(0.65, 1.1 * scale))
            }
        }
        .frame(width: 1000 * scale, height: 835 * scale)
    }
}

private extension View {
    func hardwareRegion(_ rect: CGRect, scale: CGFloat) -> some View {
        frame(width: rect.width * scale, height: rect.height * scale)
            .position(x: rect.midX * scale, y: rect.midY * scale)
    }
}

private struct MonitorStandCutout: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 463, y: 570, width: 74, height: 231), cornerRadius: 2)
        path.addRoundedRect(in: CGRect(x: 486.5, y: 650, width: 27, height: 46), cornerSize: CGSize(width: 13.5, height: 13.5))
        return path.applying(.init(scaleX: rect.width / 1000, y: rect.height / 835))
    }
}

private struct MonitorCableBevel: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 483, y: 647, width: 34, height: 54), cornerRadius: 17)
        path.addRoundedRect(in: CGRect(x: 486.5, y: 650, width: 27, height: 46), cornerSize: CGSize(width: 13.5, height: 13.5))
        return path.applying(.init(scaleX: rect.width / 1000, y: rect.height / 835))
    }
}

private struct MonitorHardwareFacet: Shape {
    enum Part {
        case standLeft, standRight, baseShell, baseTop, baseLeft, baseRight, baseFront, baseRidge
    }

    let part: Part

    init(_ part: Part) { self.part = part }

    func path(in rect: CGRect) -> Path {
        let vertices: [(CGFloat, CGFloat)]
        switch part {
        case .standLeft:
            vertices = [(464, 578), (473, 580), (473, 791), (464, 798)]
        case .standRight:
            vertices = [(531, 578), (536, 577), (536, 798), (531, 792)]
        case .baseShell:
            vertices = [(316, 808), (463, 795), (537, 795), (684, 808), (687, 823), (500, 830), (313, 823)]
        case .baseTop:
            vertices = [(317, 809), (464, 795), (536, 795), (683, 809), (500, 817)]
        case .baseLeft:
            vertices = [(317, 809), (464, 795), (489, 804), (500, 817)]
        case .baseRight:
            vertices = [(536, 795), (683, 809), (500, 817), (511, 804)]
        case .baseFront:
            vertices = [(316, 814), (500, 821), (684, 814), (685, 821), (500, 827), (315, 821)]
        case .baseRidge:
            vertices = [(318, 810), (500, 818), (682, 810)]
        }
        var path = Path()
        if let first = vertices.first {
            path.move(to: CGPoint(x: first.0, y: first.1))
            for point in vertices.dropFirst() {
                path.addLine(to: CGPoint(x: point.0, y: point.1))
            }
            if part != .baseRidge { path.closeSubpath() }
        }
        return path.applying(.init(scaleX: rect.width / 1000, y: rect.height / 835))
    }
}
