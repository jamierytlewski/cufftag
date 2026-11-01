// AVFoundation's capture objects aren't Sendable, but they're only configured on `queue`,
// per AVCaptureSession's threading guidance.
@preconcurrency import AVFoundation
import Photos
import UIKit

/// A simple camera whose shutter lives on your sleeve.
@MainActor
final class SleeveCamera: NSObject, ObservableObject {
  enum Timer: Int, CaseIterable {
    case off = 0, three = 3, ten = 10
    var next: Timer { Timer.allCases[(Timer.allCases.firstIndex(of: self)! + 1) % Timer.allCases.count] }
    var label: String { self == .off ? "Off" : "\(rawValue)s" }
  }

  @Published private(set) var isRunning = false
  @Published private(set) var isRecording = false
  @Published private(set) var recordingStarted: Date?
  @Published private(set) var position: AVCaptureDevice.Position = .back
  @Published private(set) var countdown: Int?
  @Published private(set) var flashTick = 0
  @Published private(set) var lastThumbnail: UIImage?
  @Published private(set) var problem: String?
  @Published private(set) var isCapturing = false
  @Published private(set) var isSaving = false
  @Published private(set) var hasPendingSave = false
  @Published var timer: Timer = .off

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()
  private let queue = DispatchQueue(label: "SleeveCamera.session")
  private var videoInput: AVCaptureDeviceInput?
  private var countdownTask: Task<Void, Never>?
  private let tag: TagController
  private enum Capture {
    case photo(Data)
    case video(URL)
  }
  private var pendingCapture: Capture?

  init(tag: TagController) {
    self.tag = tag
  }

  // MARK: Lifecycle

  func start() async {
    problem = nil
    guard await Self.requestAccess(.video) else {
      problem = "Camera access is off. Enable it in Settings › Jacquard."
      return
    }
    let mic = await Self.requestAccess(.audio)
    guard !Task.isCancelled else { return }
    let position = self.position
    let ok: Bool = await withCheckedContinuation { continuation in
      queue.async { [session, photoOutput, movieOutput] in
        if session.inputs.isEmpty {
          session.beginConfiguration()
          session.sessionPreset = .high
          if let device = Self.device(position),
            let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
          {
            session.addInput(input)
          }
          if mic, let audio = AVCaptureDevice.default(for: .audio),
            let input = try? AVCaptureDeviceInput(device: audio), session.canAddInput(input)
          {
            session.addInput(input)
          }
          if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
          if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
          session.commitConfiguration()
        }
        session.startRunning()
        continuation.resume(returning: session.isRunning)
      }
    }
    videoInput = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
      .first { $0.device.hasMediaType(.video) }
    guard !Task.isCancelled else {
      stop()
      return
    }
    isRunning = ok && videoInput != nil
    if !isRunning { problem = "The camera couldn't start. Check camera access and try again." }
    if isRunning && !mic { problem = "Microphone access is off. Videos will have no sound." }
  }

  func stop() {
    countdownTask?.cancel()
    countdown = nil
    if isRecording { movieOutput.stopRecording() }
    queue.async { [session] in session.stopRunning() }
    isRunning = false
  }

  // MARK: Sleeve gestures

  /// Returns true if the camera consumed the gesture.
  func handle(_ gesture: JQGesture) -> Bool {
    switch gesture {
    case .doubleTap: shutter()
    case .brushIn: flip()
    case .brushOut: toggleRecording()
    case .shortCover:
      timer = timer.next
      tag.signal(timer == .off ? .back : .confirm)
    default: return false
    }
    return true
  }

  // MARK: Actions

  func shutter() {
    guard isRunning, !isCapturing, !isRecording, !hasPendingSave else { return }
    if countdown != nil {
      countdownTask?.cancel()
      countdown = nil
      tag.signal(.pause)
      return
    }
    guard timer != .off else { return capturePhoto() }
    countdownTask = Task { [weak self] in
      guard let self else { return }
      for remaining in stride(from: self.timer.rawValue, to: 0, by: -1) {
        self.countdown = remaining
        self.tag.flash(remaining <= 3 ? [.red] : [.amber], frameMs: 150)
        if remaining <= 3 { self.tag.buzz(.tick) }
        try? await Task.sleep(for: .seconds(1))
        if Task.isCancelled { return }
      }
      self.countdown = nil
      self.capturePhoto()
    }
  }

  func capturePhoto() {
    guard isRunning, !isCapturing, !isRecording, !hasPendingSave else { return }
    guard photoOutput.connection(with: .video)?.isActive == true else {
      problem = "The camera isn't ready to take a photo. Try again."
      return
    }
    problem = nil
    isCapturing = true
    let settings = AVCapturePhotoSettings()
    if videoInput?.device.hasFlash == true { settings.flashMode = .off }
    photoOutput.capturePhoto(with: settings, delegate: self)
    flashTick += 1
  }

  func flip() {
    guard isRunning, !isRecording, !isCapturing, countdown == nil else { return }
    let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
    queue.async { [session, weak self] in
      guard let device = Self.device(newPosition),
        let input = try? AVCaptureDeviceInput(device: device)
      else {
        Task { @MainActor in self?.problem = "That camera isn't available." }
        return
      }
      session.beginConfiguration()
      let oldInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        .filter { $0.device.hasMediaType(.video) }
      for old in oldInputs {
        session.removeInput(old)
      }
      guard session.canAddInput(input) else {
        for old in oldInputs where session.canAddInput(old) { session.addInput(old) }
        session.commitConfiguration()
        Task { @MainActor in self?.problem = "Couldn't switch cameras. The previous camera is still selected." }
        return
      }
      session.addInput(input)
      session.commitConfiguration()
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.videoInput = input
          self?.position = newPosition
          self?.tag.signal(.skip)
        }
      }
    }
  }

  func toggleRecording() {
    guard isRunning, !isCapturing, !hasPendingSave, countdown == nil else { return }
    if isRecording {
      movieOutput.stopRecording()
      tag.signal(.pause)
    } else {
      guard movieOutput.connection(with: .video)?.isActive == true else {
        problem = "The camera isn't ready to record video. Try again."
        return
      }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
      movieOutput.startRecording(to: url, recordingDelegate: self)
      isRecording = true
      recordingStarted = Date()
      tag.signal(.play)
      tag.flash([.red], frameMs: 400)
    }
  }

  // MARK: Helpers

  private nonisolated static func device(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
  }

  private static func requestAccess(_ type: AVMediaType) async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: type) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
    default: return false
    }
  }

  private func save(photo data: Data) {
    pendingCapture = .photo(data)
    hasPendingSave = true
    retrySave()
  }

  private func save(video url: URL) {
    pendingCapture = .video(url)
    hasPendingSave = true
    retrySave()
  }

  func retrySave() {
    guard let capture = pendingCapture, !isSaving else { return }
    isSaving = true
    Task {
      defer {
        isSaving = false
        isCapturing = false
      }
      let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      guard status == .authorized || status == .limited else {
        problem = "Not saved. Enable Photos access in Settings, then tap Retry save before closing the app."
        tag.signal(.error)
        return
      }
      do {
        try await PHPhotoLibrary.shared().performChanges {
          let request = PHAssetCreationRequest.forAsset()
          switch capture {
          case .photo(let data):
            request.addResource(with: .photo, data: data, options: nil)
          case .video(let url):
            request.addResource(with: .video, fileURL: url, options: nil)
          }
        }
        if case .photo(let data) = capture {
          lastThumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
        }
        if case .video(let url) = capture { removeTemporaryVideo(url) }
        pendingCapture = nil
        hasPendingSave = false
        problem = nil
        tag.signal(.confirm)
      } catch {
        problem = "Not saved: \(error.localizedDescription) Tap Retry save before closing the app."
        tag.signal(.error)
      }
    }
  }

  func discardPendingCapture() {
    guard !isSaving else { return }
    if case .video(let url) = pendingCapture { removeTemporaryVideo(url) }
    pendingCapture = nil
    hasPendingSave = false
    isCapturing = false
    problem = nil
  }

  private func removeTemporaryVideo(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      NSLog("Unable to clean up temporary camera recording: %@", error.localizedDescription)
    }
  }
}

extension SleeveCamera: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
  nonisolated func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    let data = photo.fileDataRepresentation()
    Task { @MainActor in
      if let error {
        self.isCapturing = false
        self.problem = "Photo capture failed: \(error.localizedDescription)"
        self.tag.signal(.error)
      } else if let data {
        self.save(photo: data)
      } else {
        self.isCapturing = false
        self.problem = "The camera didn't return a photo. Please try again."
        self.tag.signal(.error)
      }
    }
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection], error: Error?
  ) {
    Task { @MainActor in
      self.isRecording = false
      self.recordingStarted = nil
      if let error,
        (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
        self.problem = "Recording failed: \(error.localizedDescription)"
        self.tag.signal(.error)
        self.removeTemporaryVideo(outputFileURL)
        return
      }
      self.save(video: outputFileURL)
    }
  }
}
