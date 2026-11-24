import SwiftUI

struct PresetValueSlider: View {
    let title: String
    @Binding var value: Double
    let format: (Double) -> String
    @State private var scale: PresetValueScale

    init(_ title: String, value: Binding<Double>, presets: [Double], format: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.format = format
        // Keep an existing non-preset value for this view's lifetime, so dragging
        // never changes the number or position of the slider's steps mid-gesture.
        self._scale = State(initialValue: PresetValueScale(presets: presets, currentValue: value.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsControlRow {
                Text(self.title)
            } control: {
                Text(self.format(self.value)).foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { self.scale.index(for: self.value) },
                    set: { self.value = self.scale.value(at: $0) }
                ),
                in: 0...Double(self.scale.values.count - 1),
                step: 1
            ) {
                Text(self.title)
            } minimumValueLabel: {
                Text(self.format(self.scale.values[0])).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(self.format(self.scale.values[self.scale.values.count - 1])).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
            .accessibilityLabel(self.title)
            .accessibilityValue(self.format(self.value))
        }
    }
}
