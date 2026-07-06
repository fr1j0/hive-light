import SwiftUI

/// Panel-native monochrome controls (settings redesign). Stock control
/// styles (.checkbox, .radioGroup, .switch) tint system blue; the panel's
/// color law reserves color for meaning — status lamps, git refs — so
/// controls read as structure: Color.primary opacities only.

/// A 26×15 capsule switch. On: 92% primary track with a panel-background
/// knob; off: 16% primary track with a mid-primary knob. Both knob/track
/// pairs keep contrast in light and dark themes.
struct MiniSwitch: View {
    @Binding var isOn: Bool
    /// Accessibility only — the visible label lives in the settings row.
    let label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(Color.primary.opacity(isOn ? 0.92 : 0.16))
                .frame(width: 26, height: 15)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn
                              ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                              : AnyShapeStyle(Color.primary.opacity(0.55)))
                        .padding(1.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// A compact segmented pill (the sort control). Selection is a 18% primary
/// chip inside an 8% primary container — monochrome, never accent-tinted.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 10.5, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(selected ? 0.18 : 0)))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 6.5).fill(Color.primary.opacity(0.08)))
    }
}
