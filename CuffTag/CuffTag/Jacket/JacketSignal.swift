import Foundation
import JacquardSDK

struct RGB: Equatable, Hashable {
  var red: Int
  var green: Int
  var blue: Int

  static let off = RGB(red: 0, green: 0, blue: 0)
  static let copper = RGB(red: 200, green: 116, blue: 58)
  static let indigo = RGB(red: 40, green: 60, blue: 160)
  static let cyan = RGB(red: 127, green: 227, blue: 255)
  static let white = RGB(red: 220, green: 220, blue: 220)
  static let green = RGB(red: 30, green: 200, blue: 90)
  static let amber = RGB(red: 255, green: 160, blue: 20)
  static let red = RGB(red: 230, green: 30, blue: 40)
  static let violet = RGB(red: 150, green: 70, blue: 230)
  static let pink = RGB(red: 255, green: 80, blue: 160)
}

/// One "note" of sleeve vibration.
struct HapticNote: Equatable, Hashable {
  var onMs: Int
  var offMs: Int = 0
  var amplitude: Int = 70
  var repeats: Int = 1
  var shape: PlayHapticCommand.HapticPatternType = .hapticSymbolConstOn

  var totalMs: Int { (onMs + offMs) * repeats }

  var frame: PlayHapticCommand.HapticFrame {
    .init(
      onMs: UInt32(onMs), offMs: UInt32(offMs), maxAmplitudePercent: UInt32(amplitude),
      repeatNMinusOne: UInt32(max(0, repeats - 1)), pattern: shape)
  }

  static let tick = HapticNote(onMs: 60, amplitude: 60)
  static let tap = HapticNote(onMs: 120, amplitude: 70)
  static let rise = HapticNote(onMs: 450, amplitude: 90, shape: .hapticSymbolSineIncrease)
  static let fall = HapticNote(onMs: 450, amplitude: 90, shape: .hapticSymbolSineDecrease)
  static let long = HapticNote(onMs: 900, amplitude: 100)
}

struct LightPattern: Equatable, Hashable {
  var colors: [RGB]
  var frameMs: Int = 180
  var totalMs: Int?
}

/// A named haptic + light signature. Signals are the jacket's vocabulary: each action has one,
/// so you learn by feel what just happened without looking at your phone.
struct JacketSignal: Identifiable, Hashable {
  let id: String
  let name: String
  let summary: String
  let haptics: [HapticNote]
  let light: LightPattern?

  static let hello = JacketSignal(
    id: "hello", name: "Hello", summary: "A warm rising swell — used when the jacket connects.",
    haptics: [.rise, .tap],
    light: .init(colors: [.indigo, .cyan, .copper, .cyan], frameMs: 220))
  static let play = JacketSignal(
    id: "play", name: "Play", summary: "Swell up.", haptics: [.rise],
    light: .init(colors: [.green]))
  static let pause = JacketSignal(
    id: "pause", name: "Pause", summary: "Swell down.", haptics: [.fall],
    light: .init(colors: [.amber]))
  static let skip = JacketSignal(
    id: "skip", name: "Skip", summary: "Two quick ticks.", haptics: [.tick, .tick],
    light: .init(colors: [.cyan, .off, .cyan], frameMs: 90))
  static let back = JacketSignal(
    id: "back", name: "Back", summary: "One firm tick.", haptics: [.tap],
    light: .init(colors: [.violet]))
  static let volume = JacketSignal(
    id: "volume", name: "Volume", summary: "A single light tick.", haptics: [.tick], light: nil)
  static let confirm = JacketSignal(
    id: "confirm", name: "Done", summary: "A short tap.", haptics: [.tap],
    light: .init(colors: [.white]))
  static let bookmark = JacketSignal(
    id: "bookmark", name: "Bookmark", summary: "Tap, then swell.", haptics: [.tap, .rise],
    light: .init(colors: [.copper, .copper]))
  static let shift = JacketSignal(
    id: "shift", name: "Shift", summary: "A soft tick — the next gesture is the alternate.",
    haptics: [.tick], light: .init(colors: [.violet], frameMs: 300))
  static let nudge = JacketSignal(
    id: "nudge", name: "Nudge", summary: "Three gentle taps — someone wants your attention.",
    haptics: [.tap, .tap, .tap],
    light: .init(colors: [.pink, .off, .pink, .off, .pink], frameMs: 150))
  static let alert = JacketSignal(
    id: "alert", name: "Alert", summary: "One long buzz.", haptics: [.long],
    light: .init(colors: [.red, .off, .red, .off, .red], frameMs: 120))
  static let find = JacketSignal(
    id: "find", name: "Find me", summary: "Strobes and buzzes for ten seconds.",
    haptics: Array(repeating: .long, count: 5),
    light: .init(colors: [.white, .off], frameMs: 120, totalMs: 10_000))
  static let error = JacketSignal(
    id: "error", name: "Didn't work", summary: "Two low pulses.",
    haptics: [HapticNote(onMs: 200, amplitude: 60), HapticNote(onMs: 200, amplitude: 60)],
    light: .init(colors: [.red]))

  static let library: [JacketSignal] = [
    .hello, .play, .pause, .skip, .back, .confirm, .bookmark, .shift, .nudge, .alert, .find, .error,
  ]

  static func named(_ id: String) -> JacketSignal? {
    library.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
  }
}
