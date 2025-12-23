import SwiftUI

struct RadialBreakdownView: View {
    struct Slice: Hashable {
        let label: String
        let fraction: Double
        let color: Color
    }

    let slices: [Slice]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outerR = size / 2
            let innerR = outerR * 0.62

            ZStack {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    ArcRingSlice(
                        startAngle: startAngle(for: slice),
                        endAngle: endAngle(for: slice),
                        innerRadius: innerR,
                        outerRadius: outerR,
                        center: center
                    )
                    .fill(slice.color.opacity(0.85))
                }

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: innerR * 2, height: innerR * 2)
            }
        }
    }

    private func startAngle(for slice: Slice) -> Angle {
        let idx = slices.firstIndex(of: slice) ?? 0
        let sum = slices.prefix(idx).reduce(0.0) { $0 + $1.fraction }
        return .degrees(360.0 * sum - 90.0)
    }

    private func endAngle(for slice: Slice) -> Angle {
        let idx = slices.firstIndex(of: slice) ?? 0
        let sum = slices.prefix(idx + 1).reduce(0.0) { $0 + $1.fraction }
        return .degrees(360.0 * sum - 90.0)
    }
}

private struct ArcRingSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}



