import AVFoundation
import SwiftUI

struct CameraView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var camera: SleeveCamera
  @EnvironmentObject private var tag: TagController
  @Environment(\.dismiss) private var dismiss
  @State private var flashOpacity = 0.0
  @State private var confirmDiscard = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      CameraPreview(session: camera.session)
        .ignoresSafeArea()
        .scaleEffect(x: camera.position == .front ? -1 : 1, y: 1)
        .accessibilityHidden(true)

      Color.white.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)

      if let countdown = camera.countdown {
        Text("\(countdown)")
          .font(.system(size: 160, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.4), radius: 20)
          .contentTransition(.numericText(countsDown: true))
          .animation(reduceMotion ? nil : .spring, value: countdown)
          .accessibilityLabel("Photo in \(countdown)")
      }

      VStack {
        topBar
        ScrollView {
          VStack(spacing: 12) {
            if let problem = camera.problem {
              Text(problem).font(.callout).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if camera.hasPendingSave {
              (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                if camera.isSaving {
                  ProgressView("Saving to Photos…")
                } else {
                  Button("Retry save") { camera.retrySave() }.frame(minHeight: 44)
                  Link("Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    .frame(minHeight: 44)
                  Button("Discard", role: .destructive) { confirmDiscard = true }.frame(minHeight: 44)
                }
              }
              .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            sleeveHints
          }
        }
        .defaultScrollAnchor(.bottom, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        controls
      }
      .padding(.horizontal, 20)
    }
    .statusBarHidden()
    .task { await camera.start() }
    .onDisappear { camera.stop() }
    .confirmationDialog("Discard this unsaved capture?", isPresented: $confirmDiscard) {
      Button("Discard", role: .destructive) { camera.discardPendingCapture() }
    }
    .onChange(of: camera.flashTick) { _, _ in
      guard !reduceMotion else { return }
      flashOpacity = 0.9
      withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
    }
  }

  private var topBar: some View {
    GlassEffectContainer(spacing: 12) {
      HStack {
        Button { dismiss() } label: {
          Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Close camera")
        Spacer()
        if camera.isRecording, let started = camera.recordingStarted {
          HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(started, style: .timer).font(Theme.number(.subheadline))
          }
          .padding(.horizontal, 12).padding(.vertical, 6).background(.red.opacity(0.3), in: Capsule())
        }
        Spacer()
        Button { camera.timer = camera.timer.next } label: {
          Label(camera.timer.label, systemImage: "timer")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Photo timer")
        .accessibilityValue(camera.timer.label)
      }
    }
    .foregroundStyle(.white)
    .padding(.top, 8)
  }

  private var sleeveHints: some View {
    HStack(spacing: 8) {
      hint("hand.tap.fill", "Photo")
      hint("arrow.left.to.line", "Flip")
      hint("arrow.right.to.line", camera.isRecording ? "Stop" : "Video")
      hint("hand.raised.fill", "Timer")
    }
    .opacity(tag.status.isConnected ? 1 : 0.4)
    .padding(.bottom, 12)
  }

  private func hint(_ symbol: String, _ text: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: symbol).font(.footnote)
      Text(text).font(.caption2.weight(.semibold))
    }
    .frame(maxWidth: .infinity).padding(.vertical, 8)
    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    .foregroundStyle(.white)
  }

  private var controls: some View {
    GlassEffectContainer(spacing: 16) {
      HStack {
        Button {
          UIApplication.shared.open(URL(string: "photos-redirect://")!)
        } label: {
          Group {
            if let thumb = camera.lastThumbnail {
              Image(uiImage: thumb).resizable().scaledToFill()
            } else {
              Color.white.opacity(0.1)
                .overlay(Image(systemName: "photo").foregroundStyle(.white))
            }
          }
          .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Open Photos")

        Spacer()
        Button { camera.isRecording ? camera.toggleRecording() : camera.shutter() } label: {
          ZStack {
            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
              .glassEffect(.clear.interactive(), in: Circle())
            if camera.isRecording {
              RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
            } else {
              Circle().fill(.white).frame(width: 64, height: 64)
            }
          }
        }
        .disabled(camera.isCapturing || camera.hasPendingSave || !camera.isRunning)
        .accessibilityLabel(camera.isRecording ? "Stop recording" : "Take photo")
        Spacer()
        Button { camera.flip() } label: {
          Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.title2)
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.white)
        .accessibilityLabel("Flip camera")
        .accessibilityValue(camera.position == .front ? "Front camera" : "Back camera")
      }
    }
    .padding(.bottom, 24)
  }
}

struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession

  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  }

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PreviewView, context: Context) {}
}
