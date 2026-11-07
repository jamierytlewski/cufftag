import Combine
import CoreBluetooth
import JacquardSDK

final class TestJacquardManager: JacquardManager {
  let state = CurrentValueSubject<CBManagerState, Never>(.unknown)
  let scanning = CurrentValueSubject<Bool, Never>(false)
  let advertisements = PassthroughSubject<AdvertisedTag, Never>()
  let connection = CurrentValueSubject<TagConnectionState, Error>(.preparingToConnect)
  var scanError: Error?
  var scanCount = 0
  var connectionIDs: [UUID] = []
  var knownTags: [PreConnectedTag] = []

  var centralState: AnyPublisher<CBManagerState, Never> { state.eraseToAnyPublisher() }
  var isScanning: AnyPublisher<Bool, Never> { scanning.eraseToAnyPublisher() }
  var advertisingTags: AnyPublisher<AdvertisedTag, Never> { advertisements.eraseToAnyPublisher() }
  var connectionTimeoutDuration: TimeInterval { 60 }

  init() {}
  init(publishQueue: DispatchQueue, options: [String: String]?, config: SDKConfig,
       restorePeripheralsHandler: (([UUID]) -> Void)?) {}

  func startScanning(options: [String: Any]?) throws {
    if let scanError { throw scanError }
    scanCount += 1
    scanning.send(true)
  }

  func stopScanning() { scanning.send(false) }
  func setTargetUjtFirmwareVidPid(_ targetUjtFirmwareVidPid: VidPidMid?) {}
  func preConnectedTags() -> [PreConnectedTag] { knownTags }
  func connect(_ tag: ConnectableTag) -> AnyPublisher<TagConnectionState, Error> {
    connect(tag.identifier)
  }
  func connect(_ identifier: UUID) -> AnyPublisher<TagConnectionState, Error> {
    connectionIDs.append(identifier)
    return connection.eraseToAnyPublisher()
  }
  func getConnectedTag(for identifier: UUID) -> AnyPublisher<ConnectedTag?, Never> {
    Just(nil).eraseToAnyPublisher()
  }
  func disconnect(_ tag: ConnectedTag) -> AnyPublisher<TagConnectionState, Error> {
    disconnect(tag.identifier)
  }
  func disconnect(_ identifier: UUID) -> AnyPublisher<TagConnectionState, Error> {
    Just(.disconnected(nil)).setFailureType(to: Error.self).eraseToAnyPublisher()
  }
}

struct TestAdvertisedTag: AdvertisedTag, PreConnectedTag {
  let identifier: UUID
  var displayName = "Test jacket"
  var pairingSerialNumber = "1234"
  var rssi: Float = -45
}

private struct TestComponent: Component {
  let componentID: UInt32 = 0
  let vendor = GearMetadata.GearData.Vendor()
  let product = GearMetadata.GearData.Product()
  let version: Version? = nil
  let uuid: String? = nil
}

final class TestConnectedTag: ConnectedTag, SubscribableTag {
  let identifier: UUID
  let name = "Test jacket"
  var displayName: String { name }
  var namePublisher: AnyPublisher<String, Never> { Just(name).eraseToAnyPublisher() }
  var rssiPublisher: AnyPublisher<Float, Never> { Empty().eraseToAnyPublisher() }
  var tagComponent: Component { TestComponent() }
  var gearComponent: Component? { nil }
  var connectedGear: AnyPublisher<Component?, Never> { Just(nil).eraseToAnyPublisher() }
  var firmwareUpdateManager: FirmwareUpdateManager {
    preconditionFailure("Offline connection tests must not use firmware updates")
  }

  let notifications = PassthroughSubject<Any, Never>()
  var bufferedGesture: JacquardSDK.Gesture?
  private(set) var hasGestureSubscription = false
  private(set) var subscribedBeforeReturning = false

  init(identifier: UUID) { self.identifier = identifier }

  func registerSubscriptions(_ subscriptions: (SubscribableTag) -> Void) {
    subscriptions(self)
    subscribedBeforeReturning = hasGestureSubscription
    if let bufferedGesture { notifications.send(bufferedGesture) }
  }

  func subscribe<S: NotificationSubscription>(_ subscription: S) -> AnyPublisher<S.Notification, Never> {
    if subscription is GestureNotificationSubscription { hasGestureSubscription = true }
    return notifications.compactMap { $0 as? S.Notification }.eraseToAnyPublisher()
  }

  func subscribeRawData() -> AnyPublisher<Data, Never> { Empty().eraseToAnyPublisher() }
  func subscribeRawBytes() -> AnyPublisher<[UInt8], Never> { Empty().eraseToAnyPublisher() }
  func subscribeRawDataPacket() -> AnyPublisher<Data, Never> { Empty().eraseToAnyPublisher() }
  func setTouchMode(_ mode: TouchMode, for component: Component) -> AnyPublisher<Void, Error> {
    Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
  }
  func setName(_ name: String) throws -> AnyPublisher<Void, Error> {
    Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
  }
  func enqueue<R: CommandRequest>(_ request: R) -> AnyPublisher<R.Response, Error> {
    Empty().eraseToAnyPublisher()
  }
  func enqueue<R: CommandRequest>(_ request: R, retries: Int) -> AnyPublisher<R.Response, Error> {
    enqueue(request)
  }
  func readRSSI() {}
  func send(data: Data) {}
}
