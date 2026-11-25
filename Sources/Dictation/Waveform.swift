import SwiftUI

struct Waveform: View {
    let samples: [Double]
    let processing: Bool
    var accessibilityDescription = "Voice frequency spectrum"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Recording is driven by PCM updates. A separate traveling wave marks
        // recognition after the microphone stops.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || !processing)) { context in
            WaveformFrame(samples: samples, processing: processing, time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
        }
        .accessibilityLabel(accessibilityDescription)
    }
}

struct WaveformFrame: View {
    let samples: [Double]
    let processing: Bool
    let time: Double
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: processing ? 3 : 2) {
            ForEach(0..<(processing ? 25 : 39), id: \.self) { index in
                let energy = activity(at: index)
                Capsule()
                    .fill(LinearGradient(
                        colors: processing ? [.cyan, .indigo] : [Color(red: 0.40, green: 0.94, blue: 0.78), Color(red: 0.26, green: 0.66, blue: 1)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: processing ? 3 : 2, height: 3 + 46 * energy)
                    .opacity(0.30 + 0.70 * energy)
                    .animation(reduceMotion || processing ? nil : .linear(duration: 0.045), value: energy)
            }
        }
        .frame(width: 171, height: 52)
    }

    private func activity(at index: Int) -> Double {
        if processing {
            if reduceMotion { return 0.25 }
            let phase = Double(index) * 0.48 - time * 5
            return 0.12 + 0.48 * pow((sin(phase) + 1) / 2, 1.7)
        }
        // Fold the low voice frequencies into the centre, then mirror the
        // remaining bands outward. Both sides use exactly the same live values;
        // there is no imposed diamond envelope or fixed bar-height pattern.
        let distance = abs(index - 19)
        let energy: Double
        if distance == 0 {
            energy = samples.prefix(6).max() ?? 0
        } else {
            let band = distance + 5
            energy = samples.indices.contains(band) ? samples[band] : 0
        }
        return min(1, max(0, energy))
    }
}
