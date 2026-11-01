import SwiftUI

struct PodcastsView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var store: PodcastStore
  @EnvironmentObject private var player: PodcastPlayer
  @EnvironmentObject private var media: MediaRouter
  @State private var showAdd = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          if store.podcasts.isEmpty {
            emptyState
          } else {
            if !store.inProgress.isEmpty { continueListening }
            upNext
            shows
            if !store.bookmarks.isEmpty { bookmarks }
          }
        }
        .padding(.horizontal, 20).padding(.bottom, 30)
      }
      .scrollIndicators(.hidden)
      .refreshable { await store.refreshAll() }
      .background(Theme.background)
      .navigationTitle("Podcasts")
      .navigationDestination(for: Podcast.self) { PodcastDetailView(podcastID: $0.id) }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showAdd = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("Add a show")
        }
      }
      .sheet(isPresented: $showAdd) { AddPodcastSheet() }
      .task { await store.refreshIfStale() }
      .withMiniPlayer()
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(Theme.copperLight)
      Text("Your shows, on your sleeve.").font(Theme.title(.title2))
      Text("Apple Podcasts can't be controlled by other apps, so Jacquard has its own player. Add the shows you follow — double tap to play, brush in to skip 30s, brush out to go back 15s, Cover + double tap to bookmark a moment.")
        .font(.callout).foregroundStyle(Theme.muted)
      Button("Add a show") { showAdd = true }.buttonStyle(CopperButtonStyle())
    }
    .stitchedCard()
    .padding(.top, 10)
  }

  private var continueListening: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Continue").sectionLabel()
      ScrollView(.horizontal) {
        HStack(spacing: 14) {
          ForEach(store.inProgress.prefix(8)) { episode in
            Button { play(episode) } label: { ContinueCard(episode: episode) }.buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var upNext: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Up next").sectionLabel()
      if store.upNext.isEmpty {
        Text("You're all caught up.").font(.subheadline).foregroundStyle(Theme.muted)
      }
      VStack(spacing: 4) {
        ForEach(store.upNext.prefix(12)) { episode in
          EpisodeRow(episode: episode, showPodcast: true)
        }
      }
    }
  }

  private var shows: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Shows").sectionLabel()
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 12) {
        ForEach(store.podcasts) { podcast in
          NavigationLink(value: podcast) {
            Artwork(url: podcast.artworkURL, size: nil, corner: 14)
              .aspectRatio(1, contentMode: .fit)
          }
          .accessibilityLabel(podcast.title)
          .accessibilityHint("Shows episodes")
        }
      }
    }
  }

  private var bookmarks: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Bookmarked moments").sectionLabel()
      VStack(spacing: 0) {
        ForEach(store.bookmarks.prefix(20)) { bookmark in
          Button { open(bookmark) } label: {
            HStack(spacing: 12) {
              Image(systemName: "bookmark.fill").foregroundStyle(Theme.copper)
              VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.episodeTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(bookmark.podcastTitle) · \(Duration.seconds(bookmark.seconds).formatted(.time(pattern: .hourMinuteSecond)))")
                  .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
              }
              Spacer()
              Text(bookmark.createdAt, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 10)
            .foregroundStyle(Theme.ink)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { store.removeBookmark(bookmark) }
          }
        }
      }
      .stitchedCard(padding: 14)
    }
  }

  private func play(_ episode: Episode) {
    media.activeSource = .podcasts
    player.play(episode)
  }

  private func open(_ bookmark: Bookmark) {
    guard let episode = store.episode(id: bookmark.episodeID) else { return }
    play(episode)
    player.seek(to: bookmark.seconds)
  }
}

struct ContinueCard: View {
  let episode: Episode
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var store: PodcastStore

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Artwork(url: episode.artworkURL, size: 150, corner: 16)
        .overlay(alignment: .bottomTrailing) {
          Image(systemName: "play.circle.fill").font(.title).symbolRenderingMode(.palette)
            .foregroundStyle(.black, Theme.copperLight).padding(8)
        }
      Text(episode.title).font(.footnote.weight(.semibold))
        .lineLimit(typeSize.isAccessibilitySize ? nil : 2).foregroundStyle(Theme.ink)
      if let remaining = store.remaining(for: episode) {
        Text("\(Int(remaining / 60)) min left").font(.caption2).foregroundStyle(Theme.muted)
      }
    }
    .frame(width: 150, alignment: .leading)
  }
}

struct EpisodeRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let episode: Episode
  var showPodcast = false
  @EnvironmentObject private var store: PodcastStore
  @EnvironmentObject private var player: PodcastPlayer
  @EnvironmentObject private var media: MediaRouter

  private var isCurrent: Bool { player.episode?.id == episode.id }
  private var played: Bool { store.played.contains(episode.id) }

  var body: some View {
    HStack(spacing: 12) {
      Artwork(url: episode.artworkURL, size: 52, corner: 10)
      VStack(alignment: .leading, spacing: 3) {
        if showPodcast {
          Text(episode.podcastTitle).font(.caption2.weight(.semibold)).foregroundStyle(Theme.copperLight).lineLimit(1)
        }
        Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          .foregroundStyle(played ? Theme.muted : Theme.ink)
        Text(meta).font(.caption2).foregroundStyle(Theme.muted)
      }
      Spacer()
      Button {
        if isCurrent {
          player.togglePlayPause()
        } else {
          media.activeSource = .podcasts
          player.play(episode)
        }
      } label: {
        Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 32)).foregroundStyle(Theme.copper)
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(isCurrent && player.isPlaying ? "Pause" : "Play") \(episode.title)")
    }
    .padding(.vertical, 8)
    .contextMenu {
      Button(played ? "Mark unplayed" : "Mark played", systemImage: played ? "circle" : "checkmark.circle") {
        store.setPlayed(!played, for: episode)
      }
    }
  }

  private var meta: String {
    var parts: [String] = []
    if let date = episode.publishedAt { parts.append(date.formatted(.relative(presentation: .named))) }
    if let remaining = store.remaining(for: episode) {
      let minutes = Int(remaining / 60)
      parts.append((store.progress[episode.id] ?? 0) > 30 ? "\(minutes) min left" : "\(minutes) min")
    }
    if played { parts.append("Played") }
    return parts.joined(separator: " · ")
  }
}

struct Artwork: View {
  let url: URL?
  var size: CGFloat?
  var corner: CGFloat = 12

  var body: some View {
    AsyncImage(url: url) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        ZStack {
          LinearGradient(colors: [Theme.denimBottom, Theme.denimTop], startPoint: .top, endPoint: .bottom)
          Image(systemName: "mic.fill").foregroundStyle(Theme.copper.opacity(0.7))
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: corner))
    .overlay(RoundedRectangle(cornerRadius: corner).stroke(Color.white.opacity(0.08)))
    .accessibilityHidden(true)
  }
}

struct PodcastDetailView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let podcastID: String
  @EnvironmentObject private var store: PodcastStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    if let podcast = store.podcast(id: podcastID) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
            Artwork(url: podcast.artworkURL, size: 120, corner: 18)
            VStack(alignment: .leading, spacing: 6) {
              Text(podcast.title).font(Theme.title(.title2)).accessibilityAddTraits(.isHeader)
              Text(podcast.author).font(.subheadline).foregroundStyle(Theme.muted)
              Text("\(podcast.episodes.count) episodes").font(.caption).foregroundStyle(Theme.muted)
            }
          }
          LazyVStack(spacing: 0) {
            ForEach(podcast.episodes.prefix(100)) { episode in
              EpisodeRow(episode: episode)
              Divider().opacity(0.2)
            }
          }
        }
        .padding(20)
      }
      .refreshable { await store.refresh(podcast) }
      .background(Theme.background)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Menu {
          Button("Unfollow", systemImage: "minus.circle", role: .destructive) {
            store.unsubscribe(podcast)
            dismiss()
          }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("Show options")
      }
      .withMiniPlayer()
    }
  }
}

struct AddPodcastSheet: View {
  @EnvironmentObject private var store: PodcastStore
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [PodcastSearchResult] = []
  @State private var searching = false
  @State private var adding: Set<Int> = []
  @State private var feedURL = ""
  @State private var error: String?
  @State private var searchError: String?
  @State private var hasSearched = false
  @State private var addingFeed = false

  private var validFeedURL: URL? {
    guard let url = URL(string: feedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = url.host, !host.isEmpty else { return nil }
    return url
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(results) { result in
            HStack(spacing: 12) {
              Artwork(url: result.artwork, size: 52, corner: 10)
              VStack(alignment: .leading, spacing: 2) {
                Text(result.collectionName).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let artist = result.artistName {
                  Text(artist).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
              }
              Spacer()
              if isFollowing(result) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                  .accessibilityLabel("Following")
              } else if adding.contains(result.id) {
                ProgressView()
                  .accessibilityLabel("Adding \(result.collectionName)")
              } else {
                Button { add(result) } label: {
                  Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.copper)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Follow \(result.collectionName)")
              }
            }
          }
          if let searchError {
            Label(searchError, systemImage: "exclamationmark.triangle")
              .font(.callout).foregroundStyle(.orange)
          } else if hasSearched && results.isEmpty {
            Text("No shows found. Try a different name or paste the show's RSS feed below.")
              .font(.callout).foregroundStyle(Theme.muted)
          }
        } header: {
          if searching { ProgressView("Searching…") }
        }

        Section {
          TextField("https://example.com/feed.xml", text: $feedURL)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityLabel("RSS feed URL")
          if addingFeed { ProgressView("Adding show…") }
          Button("Add by RSS URL") { addFeed() }.disabled(validFeedURL == nil || addingFeed)
        } header: {
          Text("Or paste a feed")
        } footer: {
          if let error { Text(error).foregroundStyle(.orange) }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search podcasts")
      .task(id: query) { await search() }
      .navigationTitle("Add a show")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }

  private func isFollowing(_ result: PodcastSearchResult) -> Bool {
    guard let url = result.feedUrl else { return false }
    return store.podcast(id: url.absoluteString) != nil
  }

  private func search() async {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    results = []
    searchError = nil
    hasSearched = false
    searching = false
    guard term.count > 1 else { return }
    do {
      try await Task.sleep(for: .milliseconds(450))
      searching = true
      let matches = try await store.search(term)
      try Task.checkCancellation()
      results = matches
      hasSearched = true
      searching = false
    } catch {
      guard !Task.isCancelled else { return }
      searchError = "Couldn't search: \(error.localizedDescription) Try again by editing your search."
      searching = false
    }
  }

  private func add(_ result: PodcastSearchResult) {
    guard let url = result.feedUrl else {
      error = "That show doesn't publish a public feed."
      return
    }
    adding.insert(result.id)
    error = nil
    Task {
      do { _ = try await store.subscribe(feedURL: url) } catch { self.error = error.localizedDescription }
      adding.remove(result.id)
    }
  }

  private func addFeed() {
    guard let url = validFeedURL, !addingFeed else { return }
    addingFeed = true
    error = nil
    Task {
      defer { addingFeed = false }
      do {
        _ = try await store.subscribe(feedURL: url)
        feedURL = ""
        error = nil
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
