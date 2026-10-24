import SwiftUI

/// A teardrop: pointed tip at the top, round bulb at the bottom.
/// The bulb is a circle of radius `min(width, height) / 2` sitting on the bottom edge;
/// the sides are cubic curves that leave the tip at an angle and meet the bulb tangentially.
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centerX = rect.midX
        let centerY = rect.maxY - radius
        let tipY = rect.minY
        let shoulder = (centerY - tipY) * 0.35

        var path = Path()
        path.move(to: CGPoint(x: centerX, y: tipY))
        path.addCurve(
            to: CGPoint(x: centerX + radius, y: centerY),
            control1: CGPoint(x: centerX + radius * 0.35, y: tipY + shoulder),
            control2: CGPoint(x: centerX + radius, y: centerY - radius * 0.9)
        )
        path.addArc(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: tipY),
            control1: CGPoint(x: centerX - radius, y: centerY - radius * 0.9),
            control2: CGPoint(x: centerX - radius * 0.35, y: tipY + shoulder)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("DropShape") {
    HStack(spacing: 24) {
        DropShape()
            .fill(Theme.accent)
            .frame(width: 60, height: 78)
        DropShape()
            .stroke(Theme.accent, lineWidth: 2)
            .frame(width: 120, height: 156)
    }
    .padding()
}
