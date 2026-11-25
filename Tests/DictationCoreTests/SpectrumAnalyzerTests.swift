import XCTest
@testable import DictationCore

final class SpectrumAnalyzerTests: XCTestCase {
    private func tone(_ frequency: Double, amplitude: Double = 0.35, seconds: Double = 0.2, rate: Double = 48000) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    private func feed(_ samples: [Float], to analyzer: SpectrumAnalyzer) {
        samples.withUnsafeBufferPointer { analyzer.consume($0) }
    }

    func testSilenceRemainsAtBaseline() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        feed(Array(repeating: 0, count: 24000), to: analyzer)
        XCTAssertTrue(analyzer.bands.allSatisfy { $0 == 0 })
    }

    func testDifferentPitchesMoveDifferentBars() {
        let low = SpectrumAnalyzer(sampleRate: 48000)
        let high = SpectrumAnalyzer(sampleRate: 48000)
        feed(tone(350), to: low)
        feed(tone(2800), to: high)
        let lowIndex = low.bands.indices.max(by: { low.bands[$0] < low.bands[$1] })!
        let highIndex = high.bands.indices.max(by: { high.bands[$0] < high.bands[$1] })!
        XCTAssertLessThan(abs(log2(low.frequencies[lowIndex] / 350)), 0.3)
        XCTAssertLessThan(abs(log2(high.frequencies[highIndex] / 2800)), 0.3)
        XCTAssertGreaterThan(highIndex - lowIndex, 7)
        XCTAssertLessThan(low.bands.filter { $0 > 0.7 }.count, 6)
    }

    func testPauseSettlesWithinQuarterSecond() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        feed(tone(700), to: analyzer)
        XCTAssertGreaterThan(analyzer.bands.max()!, 0.6)
        feed(Array(repeating: 0, count: 12000), to: analyzer)
        XCTAssertLessThan(analyzer.bands.max()!, 0.05)
    }

    func testQuieterSyllableDropsWithoutFlatteningAllBands() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000)
        feed(tone(500, amplitude: 0.7), to: analyzer)
        let loud = analyzer.bands.max()!
        feed(tone(500, amplitude: 0.035), to: analyzer)
        XCTAssertLessThan(analyzer.bands.max()!, loud * 0.6)
        XCTAssertTrue(analyzer.bands.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testLowSampleRateAndArbitraryBufferChunks() {
        let continuous = SpectrumAnalyzer(sampleRate: 16000)
        let chunked = SpectrumAnalyzer(sampleRate: 16000)
        let samples = tone(900, rate: 16000)
        feed(samples, to: continuous)
        for index in stride(from: 0, to: samples.count, by: 137) {
            feed(Array(samples[index..<min(index + 137, samples.count)]), to: chunked)
        }
        for (left, right) in zip(continuous.bands, chunked.bands) { XCTAssertEqual(left, right, accuracy: 1e-9) }
    }
}
