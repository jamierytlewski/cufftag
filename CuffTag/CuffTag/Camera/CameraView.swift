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
      if camera.isDemoPreview {
        DemoCameraBackdrop(position: camera.position)
          .ignoresSafeArea()
          .accessibilityHidden(true)
      } else {
        CameraPreview(session: camera.session)
          .ignoresSafeArea()
          .scaleEffect(x: camera.position == .front ? -1 : 1, y: 1)
          .accessibilityHidden(true)
      }

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
        .frame(minWidth: 44, minHeight: 44)
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
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                            count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
      hint("hand.tap.fill", "Photo")
      hint("hand.raised.fill", "3s Photo")
      hint("arrow.left.to.line", "Flip")
      hint("arrow.right.to.line", camera.isRecording ? "Stop" : "Video")
    }
    .opacity(tag.status.isConnected ? 1 : 0.4)
    .padding(.bottom, 12)
  }

  private func hint(_ symbol: String, _ text: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: symbol).font(.footnote)
      Text(text).font(.caption2.weight(.semibold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
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

/// Synthetic viewfinder backdrop used when capturing App Store screenshots on the Simulator.
private struct DemoCameraBackdrop: View {
  let position: AVCaptureDevice.Position

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.08, green: 0.14, blue: 0.28),
          Color(red: 0.18, green: 0.26, blue: 0.42),
          Color(red: 0.48, green: 0.34, blue: 0.28),
          Color(red: 0.12, green: 0.16, blue: 0.26),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      // Subtle rule-of-thirds composition grid and focus reticle
      GeometryReader { geo in
        let w = geo.size.width
        let h = geo.size.height
        Path { p in
          p.move(to: CGPoint(x: w / 3, y: 0))
          p.addLine(to: CGPoint(x: w / 3, y: h))
          p.move(to: CGPoint(x: w * 2 / 3, y: 0))
          p.addLine(to: CGPoint(x: w * 2 / 3, y: h))
          p.move(to: CGPoint(x: 0, y: h / 3))
          p.addLine(to: CGPoint(x: w, y: h / 3))
          p.move(to: CGPoint(x: 0, y: h * 2 / 3))
          p.addLine(to: CGPoint(x: w, y: h * 2 / 3))
        }
        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)

        RoundedRectangle(cornerRadius: 16)
          .stroke(Theme.copperLight.opacity(0.85), lineWidth: 1.5)
          .frame(width: 116, height: 116)
          .position(x: w * 0.5, y: h * 0.42)
      }
    }
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

  func updateUIView(_ uiView: PreviewView, context: Context) {
    uiView.previewLayer.session = session
  }
}
