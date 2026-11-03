import SwiftUI

/// Control segmentado del manual v2: cápsula `fill` con el segmento elegido en
/// `bg-grouped-2`. Cada segmento ocupa al menos 44 pt de alto para el dedo.
public struct CapsuleSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    public init(_ title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Spacing.s8)
                        .frame(maxWidth: .infinity, minHeight: ControlSize.hitTarget - 4)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Palette.bgGrouped2)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.fill, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
