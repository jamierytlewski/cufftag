import Combine
import CoreBluetooth
import Foundation
import JacquardSDK

typealias JQGesture = JacquardSDK.Gesture

struct DiscoveredTag: Identifiable {
  let id: UUID
  let name: String
  let tag: ConnectableTag
  let alreadyConnected: Bool
}

struct GestureEvent: Identifiable, Equatable {
  enum Source { case jacket, screen }

  let id = UUID()
  let gesture: JQGesture
  let date: Date
  var source: Source = .jacket
}

/// Owns the Jacquard SDK manager: pairing, auto-reconnect, gestures, battery, haptics and LEDs.
@MainActor
final class TagController: ObservableObject {
  enum Status: Equatable {
    case bluetoothUnavailable(String)
    case notPaired
    case connecting(String)
    case connected
    case disconnected(String)

    var label: String {
      switch self {
      case .bluetoothUnavailable(let reason): return reason
      case .notPaired: return "No tag paired"
      case .connecting(let step): return step
      case .connected: return "Connected"
      case .disconnected(let reason): return reason
      }
    }

    var isConnected: Bool { self == .connected }
  }

  @Published private(set) var status: Status = .notPaired
  @Published private(set) var isScanning = false
  @Published private(set) var scanningProblem: String?
  @Published private(set) var discoveredTags: [DiscoveredTag] = []
  @Published private(set) var tagName: String?
  @Published private(set) var gearName: String?
  @Published private(set) var firmwareVersion: String?
  @Published private(set) var batteryLevel: Int?
  @Published private(set) var isCharging = false
  @Published private(set) var recentGestures: [GestureEvent] = []
  @Published private(set) var lastGesture: GestureEvent?
  @Published private(set) var savedTagID: UUID? {
    didSet { defaults.set(savedTagID?.uuidString, forKey: Self.savedTagKey) }
  }

  /// Called for every recognised gesture, after haptic confirmation.
  var onGesture: ((JQGesture) -> Void)?

  var hasGear: Bool { gearName != nil }

  private static let savedTagKey = "savedTagID"
  private static let restoreIdentifier = "CuffTagRestoreIdentifier"

  private var manager: JacquardManager!
  private let defaults: UserDefaults
  private var bag = Set<AnyCancellable>()
  private var connectionCancellable: AnyCancellable?
  private var tagBag = Set<AnyCancellable>()
  private var subscriptionBag = Set<AnyCancellable>()
  private var oneShots = [UUID: AnyCancellable]()
  private var currentTag: ConnectedTag?
  private var centralPoweredOn = false
  private var scanningRequested = false

  init(manager suppliedManager: JacquardManager? = nil, defaults: UserDefaults = .standard) {
    self.defaults = defaults
    savedTagID = defaults.string(forKey: Self.savedTagKey).flatMap(UUID.init)
    status = savedTagID == nil ? .notPaired : .connecting("Waiting for Bluetooth…")

    // Cloud features (firmware updates) are gone, so no API key is needed for local BLE use.
    manager = suppliedManager ?? JacquardManagerImplementation(
      publishQueue: .main,
      options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier],
      config: SDKConfig(apiKey: "local-only")
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.reconnectSavedTag() }
    }

    manager.centralState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.handleCentralState($0) }
      .store(in: &bag)

    manager.isScanning
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.isScanning = $0 }
      .store(in: &bag)

    manager.advertisingTags
      .receive(on: DispatchQueue.main)
      .sink { [weak self] tag in
        guard let self, !self.discoveredTags.contains(where: { $0.id == tag.identifier }) else { return }
        self.discoveredTags.append(
          DiscoveredTag(id: tag.identifier, name: tag.displayName, tag: tag, alreadyConnected: false))
      }
      .store(in: &bag)
  }

  // MARK: - Pairing

  func startScanning() {
    scanningRequested = true
    scanningProblem = nil
    scanIfReady()
  }

  private func scanIfReady() {
    guard scanningRequested, centralPoweredOn, !isScanning else { return }
    discoveredTags = manager.preConnectedTags().map {
      DiscoveredTag(id: $0.identifier, name: $0.displayName, tag: $0, alreadyConnected: true)
    }
    do {
      try manager.startScanning(options: nil)
    } catch {
      scanningProblem = "Couldn't look for tags: \(error.localizedDescription)"
    }
  }

  func stopScanning() {
    scanningRequested = false
    manager.stopScanning()
  }

  func pair(_ item: DiscoveredTag) {
    guard centralPoweredOn else { return }
    stopScanning()
    if let previous = savedTagID, previous != item.id {
      disconnect(previous)
    }
    connect(manager.connect(item.tag), tagID: item.id, label: "Connecting to \(item.name)…")
  }

  func forgetTag() {
    if let id = savedTagID { disconnect(id) }
    connectionCancellable?.cancel()
    connectionCancellable = nil
    clearTag()
    savedTagID = nil
    status = .notPaired
  }

  // MARK: - Connection

  func reconnectSavedTag() {
    guard centralPoweredOn, let id = savedTagID, connectionCancellable == nil else { return }
    connect(manager.connect(id), tagID: id, label: "Looking for your jacket…")
  }

  /// Waits (e.g. when launched in the background by a Shortcut) for the jacket to connect.
  func waitUntilConnected(timeout: TimeInterval = 8) async -> Bool {
    if currentTag != nil { return true }
    reconnectSavedTag()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      try? await Task.sleep(for: .milliseconds(200))
      if Task.isCancelled { return false }
      reconnectSavedTag()
      if currentTag != nil {
        // Give the gear a moment to report itself so haptics work.
        try? await Task.sleep(for: .milliseconds(400))
        return true
      }
    }
    return false
  }

  private func handleCentralState(_ state: CBManagerState) {
    switch state {
    case .poweredOn:
      centralPoweredOn = true
      if savedTagID == nil { status = .notPaired }
      reconnectSavedTag()
      scanningProblem = nil
      scanIfReady()
    case .poweredOff:
      bluetoothLost("Bluetooth is off")
    case .unauthorized:
      bluetoothLost("Bluetooth permission denied — enable it in Settings")
    case .unsupported:
      bluetoothLost("Bluetooth LE isn't supported on this device")
    case .unknown, .resetting:
      bluetoothLost("Waiting for Bluetooth…")
    @unknown default:
      bluetoothLost("Bluetooth is unavailable")
    }
  }

  private func bluetoothLost(_ reason: String) {
    centralPoweredOn = false
    isScanning = false
    discoveredTags.removeAll()
    connectionCancellable?.cancel()
    connectionCancellable = nil
    clearTag()
    status = .bluetoothUnavailable(reason)
  }

  private func connect(
    _ publisher: AnyPublisher<TagConnectionState, Error>, tagID: UUID, label: String
  ) {
    connectionCancellable?.cancel()
    status = .connecting(label)
    // receive(on:) guarantees completion is delivered after the assignment below.
    connectionCancellable =
      publisher
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          guard let self else { return }
          self.connectionCancellable = nil
          self.clearTag()
          if case .failure(let error) = completion {
            self.status = .disconnected(Self.describe(error))
          } else {
            self.status = .disconnected("Disconnected")
          }
        },
        receiveValue: { [weak self] state in
          self?.handle(state, tagID: tagID)
        })
  }

  private func handle(_ state: TagConnectionState, tagID: UUID) {
    switch state {
    case .preparingToConnect:
      status = .connecting("Preparing…")
    case .connecting:
      status = .connecting("Connecting…")
    case .initializing:
      status = .connecting("Saying hello to your tag…")
    case .configuring:
      status = .connecting("Configuring…")
    case .firmwareUpdateInitiated, .firmwareTransferring, .firmwareTransferCompleted,
      .firmwareExecuting:
      status = .connecting("Tag is updating…")
    case .connected(let tag):
      let isFirstPair = savedTagID != tagID
      savedTagID = tagID
      attach(tag)
      status = .connected
      if isFirstPair { celebrate() }
    case .disconnected(let error):
      clearTag()
      status = .disconnected(error.map(Self.describe) ?? "Out of range — reconnecting…")
    }
  }

  private func disconnect(_ id: UUID) {
    fireAndForget(manager.disconnect(id).map { _ in () }.eraseToAnyPublisher())
  }

  private func attach(_ tag: ConnectedTag) {
    tagBag.removeAll()
    currentTag = tag
    firmwareVersion = tag.tagComponent.version?.description

    tag.namePublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.tagName = $0 }
      .store(in: &tagBag)

    tag.connectedGear
      .receive(on: DispatchQueue.main)
      .sink { [weak self] gear in
        guard let self else { return }
        self.gearName = gear.map { Self.gearDisplayName($0) }
        if let gear, gear.capabilities.contains(.gesture) {
          self.fireAndForget(tag.setTouchMode(.gesture, for: gear))
        }
      }
      .store(in: &tagBag)

    tag.registerSubscriptions { [weak self] subscribable in
      // The SDK releases cached wake-up gestures as soon as this closure returns.
      self?.createSubscriptions(subscribable)
    }

    refreshBattery()
  }

  private func createSubscriptions(_ tag: SubscribableTag) {
    subscriptionBag.removeAll()
    tag.subscribe(GestureNotificationSubscription())
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.didReceive($0) }
      .store(in: &subscriptionBag)

    tag.subscribe(BatteryStatusNotificationSubscription())
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.update(battery: $0) }
      .store(in: &subscriptionBag)
  }

  private func clearTag() {
    tagBag.removeAll()
    subscriptionBag.removeAll()
    currentTag = nil
    gearName = nil
    tagName = nil
    firmwareVersion = nil
    batteryLevel = nil
    isCharging = false
  }

  // MARK: - Gestures

  private func didReceive(_ gesture: JQGesture, source: GestureEvent.Source = .jacket) {
    guard gesture != .noInference else { return }
    let event = GestureEvent(gesture: gesture, date: Date(), source: source)
    lastGesture = event
    recentGestures.insert(event, at: 0)
    if recentGestures.count > 25 { recentGestures.removeLast() }
    onGesture?(gesture)
  }

  /// Lets the UI simulate a gesture (handy for testing without the jacket).
  func simulate(_ gesture: JQGesture) {
    didReceive(gesture, source: .screen)
  }

  // MARK: - Battery

  func refreshBattery(completion: ((Int?) -> Void)? = nil) {
    guard let tag = currentTag else {
      completion?(batteryLevel)
      return
    }
    let id = UUID()
    oneShots[id] = tag.enqueue(BatteryStatusCommand())
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] result in
          self?.oneShots[id] = nil
          if case .failure = result { completion?(self?.batteryLevel) }
        },
        receiveValue: { [weak self] status in
          self?.update(battery: status)
          completion?(Int(status.batteryLevel))
        })
  }

  private func update(battery: BatteryStatus) {
    batteryLevel = Int(battery.batteryLevel)
    isCharging = battery.chargingState == .charging
  }

  // MARK: - Haptics & LEDs

  var canBuzz: Bool {
    currentTag?.gearComponent?.capabilities.contains(.haptic) == true
  }

  /// Plays a named haptic + light signature on the jacket.
  func signal(_ signal: JacketSignal) {
    for (index, note) in signal.haptics.enumerated() {
      let delay = signal.haptics.prefix(index).reduce(0) { $0 + $1.totalMs + 120 }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
        self?.buzz(note)
      }
    }
    if let light = signal.light {
      flash(light.colors, frameMs: light.frameMs, totalMs: light.totalMs)
    }
  }

  /// Vibrates the sleeve. Returns false when no haptic-capable gear is attached.
  @discardableResult
  func buzz(_ note: HapticNote) -> Bool {
    guard let tag = currentTag, let gear = tag.gearComponent, gear.capabilities.contains(.haptic),
      let request = try? PlayHapticCommand(frame: note.frame, component: gear)
    else { return false }
    fireAndForget(tag.enqueue(request))
    return true
  }

  /// Flashes the LED on the tag (the jacket itself has no LED).
  @discardableResult
  func flash(_ colors: [RGB], frameMs: Int = 180, totalMs: Int? = nil) -> Bool {
    guard let tag = currentTag else { return false }
    let frames = (colors + [.off]).map {
      PlayLEDPatternCommand.Frame(
        color: .init(red: $0.red, green: $0.green, blue: $0.blue), durationMs: frameMs)
    }
    let duration = totalMs ?? frameMs * frames.count
    for component in [tag.tagComponent, tag.gearComponent].compactMap({ $0 })
    where component.capabilities.contains(.led) {
      if let request = try? PlayLEDPatternCommand(
        frames: frames, durationMs: duration, component: component)
      {
        fireAndForget(tag.enqueue(request))
      }
    }
    return true
  }

  /// Breathes the tag LED in a colour (used during onboarding to sync with the screen).
  func breathe(_ color: RGB, seconds: Int = 4) {
    guard let tag = currentTag,
      let request = try? PlayLEDPatternCommand(
        color: .init(red: color.red, green: color.green, blue: color.blue),
        durationMs: seconds * 1000, component: tag.tagComponent, patternType: .breathing)
    else { return }
    fireAndForget(tag.enqueue(request))
  }

  func rename(_ name: String) {
    guard let tag = currentTag, let publisher = try? tag.setName(name) else { return }
    fireAndForget(publisher)
  }

  func celebrate() {
    signal(.hello)
  }

  // MARK: - Helpers

  private func fireAndForget<T>(_ publisher: AnyPublisher<T, Error>) {
    let id = UUID()
    oneShots[id] = publisher.receive(on: DispatchQueue.main).sink(
      receiveCompletion: { [weak self] _ in self?.oneShots[id] = nil },
      receiveValue: { _ in })
  }

  private static func gearDisplayName(_ gear: Component) -> String {
    let name = gear.product.name
    return name.isEmpty ? "Jacquard gear" : name
  }

  static func describe(_ error: Error) -> String {
    guard let error = error as? TagConnectionError else { return error.localizedDescription }
    switch error {
    case .bluetoothDeviceNotFound: return "Tag not found — try pairing again"
    case .connectionTimeout: return "Timed out — is the tag charged and nearby?"
    case .bluetoothPowerOff: return "Bluetooth is off"
    case .peerRemovedPairingInfo:
      return "Tag forgot this phone — forget the tag in iOS Bluetooth settings, then re-pair"
    case .unconnectableTag: return "This tag can't be connected"
    default: return "Connection problem — reconnecting…"
    }
  }
}
