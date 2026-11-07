import AVFoundation
import Foundation

/// Plays a loud, bright chirp so you can find your phone from the sleeve.
@MainActor
final class PhoneFinder: ObservableObject {
  @Published private(set) var isRinging = false

  private var audioPlayer: AVAudioPlayer?
  private var previousVolume: Float?
  private let volume: VolumeController
  init(volume: VolumeController) {
    self.volume = volume
  }

  func ring(seconds: Double = 12) {
    if isRinging {
      stop()
      return
    }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default)
    try? session.setActive(true)
    guard let audio = try? AVAudioPlayer(data: Self.chirp()) else { return }
    audio.numberOfLoops = Int(seconds / Self.loopSeconds)
    audio.volume = 1
    audio.play()
    audioPlayer = audio
    previousVolume = session.outputVolume
    volume.set(1)
    isRinging = true
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      if self?.audioPlayer === audio { self?.stop() }
    }
  }

  func stop() {
    audioPlayer?.stop()
    audioPlayer = nil
    if let previousVolume { volume.set(previousVolume) }
    previousVolume = nil
    isRinging = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private static let loopSeconds = 1.0

  /// A rising three-note chime followed by silence, as 16-bit mono WAV data.
  private static func chirp() -> Data {
    let sampleRate = 44_100
    let notes: [Double] = [1318.5, 1760, 2637]  // E6, A6, E7
    let noteLength = Int(Double(sampleRate) * 0.12)
    let total = Int(Double(sampleRate) * loopSeconds)
    var samples = [Int16](repeating: 0, count: total)
    for (n, frequency) in notes.enumerated() {
      let start = n * (noteLength + Int(Double(sampleRate) * 0.03))
      for i in 0..<noteLength where start + i < total {
        let t = Double(i) / Double(sampleRate)
        let envelope = min(1, Double(i) / 300) * (1 - Double(i) / Double(noteLength))
        let value = sin(2 * .pi * frequency * t) * envelope * 0.95
        samples[start + i] = Int16(value * Double(Int16.max))
      }
    }
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = samples.count * 2
    data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1))
    append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
    append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
    samples.forEach { append($0) }
    return data
  }
}
