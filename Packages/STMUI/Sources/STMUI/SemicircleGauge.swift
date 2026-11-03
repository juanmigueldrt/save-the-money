import SwiftUI
import STMCore

/// Gauge semicircular de la plantilla 50/30/20: el arco de fondo es lo asignado
/// y el de color, la parte ya gastada.
public struct SemicircleGauge: View {
    public var progress: GroupProgress
    public var lineWidth: CGFloat

    public init(progress: GroupProgress, lineWidth: CGFloat = 14) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    private var tint: Color {
        progress.isOver ? Palette.negative : progress.group.color
    }

    public var body: some View {
        VStack(spacing: Spacing.s8) {
            // El arco va solo y las cifras debajo: en tres columnas de iPhone no caben dentro.
            ZStack(alignment: .bottom) {
                SemicircleArc(fraction: 1)
                    .stroke(Palette.fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                SemicircleArc(fraction: progress.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Text("\(Int((progress.fraction * 100).rounded())) %")
                    .font(Typography.subheadlineEmphasis.monospacedDigit())
                    .foregroundStyle(Palette.label)
            }
            .padding(lineWidth / 2)
            .aspectRatio(2, contentMode: .fit)
            VStack(spacing: 2) {
                Text(progress.group.title)
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                Text(progress.spent.formatted())
                    .font(Typography.footnote.monospacedDigit())
                    .foregroundStyle(Palette.label)
                Text("de \(progress.allocated.formatted())")
                    .font(Typography.caption1.monospacedDigit())
                    .foregroundStyle(Palette.labelSecondary)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.group.title): \(progress.spent.formatted()) gastados de \(progress.allocated.formatted())")
    }
}

/// Medio círculo abierto por abajo, de izquierda a derecha, recortado a `fraction`.
struct SemicircleArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + 180 * min(max(fraction, 0), 1)),
                    clockwise: false)
        return path
    }
}

#Preview {
    HStack {
        SemicircleGauge(progress: GroupProgress(group: .needs, allocated: Money(minor: 200_000), spent: Money(minor: 142_000)))
        SemicircleGauge(progress: GroupProgress(group: .wants, allocated: Money(minor: 120_000), spent: Money(minor: 131_000)))
    }
    .padding()
}
