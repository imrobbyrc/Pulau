import SwiftUI

/// Glass switch used across settings. Knob slides with the shared spring; the on-state
/// track picks up Liquid Glass on macOS 26 and falls back to a bright fill below.
struct GlassToggle: View {
    @Binding var isOn: Bool
    var label: String? = nil

    var body: some View {
        Button {
            withAnimation(Motion.spring) { isOn.toggle() }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(isOn ? AnyShapeStyle(.white.opacity(0.24)) : AnyShapeStyle(.white.opacity(0.1)))
                if isOn, #available(macOS 26.0, *) {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.interactive().tint(.white.opacity(0.14)),
                                     in: Capsule(style: .continuous))
                }
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: 38, height: 22)
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? "Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Segmented glass selector: a single capsule slides between options with
/// matched geometry, so the selection moves like a liquid blob.
struct GlassSegmentedPicker<Option: Hashable>: View {
    let options: [(value: Option, label: String)]
    @Binding var selection: Option
    @Namespace private var segment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Design.spacingS) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(reduceMotion ? nil : Motion.spring) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.mono(11, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? .white : .white.opacity(0.65))
                        .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                        .padding(.horizontal, Design.spacingM)
                        .padding(.vertical, 5)
                        .background {
                            if selection == option.value {
                                capsule
                                    .matchedGeometryEffect(id: "glass-segment", in: segment)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var capsule: some View {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.06))
                .glassEffect(.regular.interactive().tint(.black.opacity(0.25)), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(Design.strokeBright), lineWidth: 0.8))
        } else {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(Design.strokeBright), lineWidth: 0.8))
        }
    }
}
