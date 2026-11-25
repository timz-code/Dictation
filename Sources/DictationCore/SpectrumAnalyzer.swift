import Accelerate
import Foundation

/// Independent, log-spaced frequency bands from microphone PCM. Slow gain
/// adaptation preserves syllable dynamics without saturating on a loud mic.
public final class SpectrumAnalyzer {
    public static let bandCount = 25
    public private(set) var bands = Array(repeating: 0.0, count: bandCount)
    public let frequencies: [Double]
    private let sampleRate: Double
    private let size: Int
    private let hop: Int
    private let transform: vDSP_DFT_Setup
    private var ring: [Float]
    private var window: [Float]
    private let windowSum: Float
    private var input: [Float]
    private var imaginaryInput: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private let ranges: [ClosedRange<Int>]
    private var cursor = 0
    private var count = 0
    private var sinceTransform = 0
    private var referenceDB = -32.0

    public init(sampleRate: Double) {
        precondition(sampleRate.isFinite && sampleRate >= 8000)
        self.sampleRate = sampleRate
        let size = sampleRate > 32000 ? 2048 : 1024
        self.size = size
        hop = size / 4
        transform = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)!
        ring = Array(repeating: 0, count: size)
        input = ring
        imaginaryInput = ring
        real = ring
        imaginary = ring
        window = ring
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowSum = window.reduce(0, +)
        let low = 85.0
        let high = min(7600, sampleRate * 0.46)
        let edges = (0...Self.bandCount).map { low * pow(high / low, Double($0) / Double(Self.bandCount)) }
        frequencies = (0..<Self.bandCount).map { sqrt(edges[$0] * edges[$0 + 1]) }
        ranges = (0..<Self.bandCount).map { index in
            let first = max(1, Int((edges[index] * Double(size) / sampleRate).rounded()))
            let last = min(size / 2 - 1, max(first, Int((edges[index + 1] * Double(size) / sampleRate).rounded()) - 1))
            return first...last
        }
    }

    public func consume(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            ring[cursor] = sample.isFinite ? sample : 0
            cursor = (cursor + 1) % size
            count = min(size, count + 1)
            sinceTransform += 1
            if count == size && sinceTransform >= hop {
                analyze()
                sinceTransform = 0
            }
        }
    }

    private func analyze() {
        var sumSquares = 0.0
        for index in 0..<size {
            let value = ring[(cursor + index) % size]
            sumSquares += Double(value * value)
            input[index] = value * window[index]
        }
        vDSP_DFT_Execute(transform, input, imaginaryInput, &real, &imaginary)
        let elapsed = Double(hop) / sampleRate
        let rmsDB = 10 * log10(max(1e-12, sumSquares / Double(size)))
        referenceDB = max(-32, max(rmsDB + 6, referenceDB - elapsed * 8))
        let gate = min(1, max(0, (rmsDB + 60) / 14))
        for band in 0..<Self.bandCount {
            var peakPower: Float = 0
            for bin in ranges[band] {
                peakPower = max(peakPower, real[bin] * real[bin] + imaginary[bin] * imaginary[bin])
            }
            let magnitude = Double(sqrt(peakPower) * 2 / windowSum)
            let tilt = max(0, 3 * log2(frequencies[band] / 250))
            let decibels = 20 * log10(max(1e-9, magnitude)) + tilt
            let relative = min(1, max(0, (decibels - referenceDB + 38) / 38))
            let target = pow(relative, 1.35) * gate
            let response = 1 - exp(-elapsed / (target > bands[band] ? 0.012 : 0.065))
            bands[band] += (target - bands[band]) * response
        }
    }

    deinit { vDSP_DFT_DestroySetup(transform) }
}
