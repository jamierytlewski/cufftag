import AVKit
import SwiftUI

struct MiniPlayerModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PodcastPlayer
  @State private var showNowPlaying = false

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom) {
        if player.episode != nil {
          MiniPlayer { showNowPlaying = true }
            .padding(.horizontal, 12).padding(.bottom, 6)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
      .sheet(isPresented: $showNowPlaying) { NowPlayingView() }
  }
}

extension View {
  func withMiniPlayer() -> some View { modifier(MiniPlayerModifier()) }
}

struct MiniPlayer: View {
  var open: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PodcastPlayer
  @EnvironmentObject private var media: MediaRouter

  var body: some View {
    if let episode = player.episode {
      (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
        Button(action: open) {
          HStack(spacing: 12) {
            Group {
              if let art = player.artwork {
                Image(uiImage: art).resizable().scaledToFill()
              } else {
                Artwork(url: episode.artworkURL, size: 44, corner: 10)
              }
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(1)
              Text(episode.podcastTitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now playing: \(episode.title), \(episode.podcastTitle)")
        .accessibilityHint("Opens the full player")
        HStack(spacing: 8) {
          Button { player.togglePlayPause() } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
              .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
              .frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
          Button { player.skip(by: player.skipForwardSeconds) } label: {
            Image(systemName: "goforward.30").font(.title3)
              .frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel("Skip forward \(Int(player.skipForwardSeconds)) seconds")
        }
      }
      .foregroundStyle(Theme.ink)
      .padding(10)
      .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
      .overlay(alignment: .bottom) {
        GeometryReader { geo in
          Capsule().fill(Theme.copper)
            .frame(width: geo.size.width * progress, height: 2)
        }
        .frame(height: 2).padding(.horizontal, 16)
      }
    }
  }

  private var progress: CGFloat {
    player.duration > 0 ? CGFloat(min(player.currentTime / player.duration, 1)) : 0
  }
}

struct NowPlayingView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PodcastPlayer
  @EnvironmentObject private var store: PodcastStore
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var settings: GestureSettings
  @State private var scrubbing: Double?
  @State private var bookmarked = false

  private let rates: [Float] = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0]

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        HStack {
          Text("Now Playing").font(.headline).accessibilityAddTraits(.isHeader)
          Spacer()
          Button("Close player", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
        }
        if let episode = player.episode {
          Group {
            if let art = player.artwork {
              Image(uiImage: art).resizable().scaledToFit()
            } else {
              Artwork(url: episode.artworkURL, size: nil, corner: 28)
            }
          }
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: typeSize.isAccessibilitySize ? 180 : 320)
          .clipShape(RoundedRectangle(cornerRadius: 28))
          .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
          .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.9)
          .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
          .accessibilityHidden(true)

          VStack(spacing: 6) {
            Text(episode.title).font(Theme.title(.title3)).multilineTextAlignment(.center)
            Text(episode.podcastTitle).font(.subheadline).foregroundStyle(Theme.copperLight)
          }
          .padding(.horizontal)

          scrubber
          transport
          extras
          sleeveLegend
        }
      }
      .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
    }
    .background(Theme.background)
    .presentationDragIndicator(.visible)
  }

  private var scrubber: some View {
    VStack(spacing: 6) {
      Slider(
        value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
        in: 0...max(player.duration, 1)
      ) { editing in
        if !editing, let value = scrubbing {
          player.seek(to: value)
          scrubbing = nil
        }
      }
      .tint(Theme.copper)
      .accessibilityLabel("Playback position")
      .accessibilityValue("\(format(scrubbing ?? player.currentTime)) of \(format(player.duration))")
      HStack {
        Text(format(scrubbing ?? player.currentTime))
        Spacer()
        Text("-" + format(max(player.duration - (scrubbing ?? player.currentTime), 0)))
      }
      .font(Theme.number(.caption)).foregroundStyle(Theme.muted)
    }
  }

  private var transport: some View {
    HStack {
      Button { player.skip(by: -player.skipBackSeconds) } label: {
        Image(systemName: "gobackward.15").font(.system(size: 30))
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Skip back \(Int(player.skipBackSeconds)) seconds")
      Spacer(minLength: 12)
      Button { player.togglePlayPause() } label: {
        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 76)).foregroundStyle(Theme.copper)
          .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
      }
      .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
      Spacer(minLength: 12)
      Button { player.skip(by: player.skipForwardSeconds) } label: {
        Image(systemName: "goforward.30").font(.system(size: 30))
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Skip forward \(Int(player.skipForwardSeconds)) seconds")
    }
    .foregroundStyle(Theme.ink)
  }

  private var extras: some View {
    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout())) {
      Menu {
        ForEach(rates, id: \.self) { rate in
          Button { player.rate = rate } label: {
            if rate == player.rate { Label(rateLabel(rate), systemImage: "checkmark") } else { Text(rateLabel(rate)) }
          }
        }
      } label: {
        Text(rateLabel(player.rate)).font(Theme.number(.subheadline))
          .padding(.horizontal, 12).padding(.vertical, 6)
          .frame(minWidth: 44, minHeight: 44)
          .background(Capsule().fill(Color.white.opacity(0.08)))
      }
      .accessibilityLabel("Playback speed")
      .accessibilityValue(rateLabel(player.rate))
      if !typeSize.isAccessibilitySize { Spacer() }
      Button {
        if let episode = player.episode {
          store.addBookmark(episode, at: player.currentTime)
          tag.signal(.bookmark)
          bookmarked = true
        }
      } label: {
        Image(systemName: bookmarked ? "bookmark.fill" : "bookmark").font(.title3)
          .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Bookmark this moment")
      .accessibilityValue(bookmarked ? "Bookmarked" : "")
      if !typeSize.isAccessibilitySize { Spacer() }
      Button { player.playNextEpisode() } label: {
        Image(systemName: "forward.end.fill").font(.title3).frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Next episode")
      if !typeSize.isAccessibilitySize { Spacer() }
      RoutePicker().frame(width: 44, height: 44)
    }
    .foregroundStyle(Theme.ink)
    .onChange(of: player.episode?.id) { _, _ in bookmarked = false }
  }

  private var sleeveLegend: some View {
    let entries: [(JQGesture, Bool)] = JQGesture.jacketGestures.map { ($0, false) }
      + (settings.coverIsShift ? GestureSettings.chordGestures.map { ($0, true) } : [])
    let mapped = entries.compactMap { gesture, shifted -> (String, String)? in
      let action = settings.action(for: gesture, shifted: shifted)
      guard action.kind != .none, action.kind.category == .media else { return nil }
      return ((shifted ? "Cover + " : "") + gesture.friendlyName, action.kind.title)
    }
    return VStack(alignment: .leading, spacing: 6) {
      Text("On your sleeve").sectionLabel()
      ForEach(mapped, id: \.0) { gesture, action in
        HStack {
          Text(gesture).foregroundStyle(Theme.glow)
          Spacer()
          Text(action).foregroundStyle(Theme.muted)
        }
        .font(.caption)
      }
    }
    .stitchedCard(padding: 14, tint: Theme.glow)
  }

  private func rateLabel(_ rate: Float) -> String {
    rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
  }

  private func format(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
  }
}

struct RoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.tintColor = .white
    view.activeTintColor = UIColor(Theme.copper)
    return view
  }
  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
