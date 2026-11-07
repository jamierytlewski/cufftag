import Foundation

enum PodcastError: LocalizedError {
  case invalidFeed
  case noFeedURL

  var errorDescription: String? {
    switch self {
    case .invalidFeed: return "That doesn't look like a podcast feed."
    case .noFeedURL: return "This show doesn't publish a public RSS feed."
    }
  }
}

/// Subscriptions, episodes and listening progress, persisted in Application Support.
@MainActor
final class PodcastStore: ObservableObject {
  @Published private(set) var podcasts: [Podcast] = []
  @Published private(set) var progress: [String: Double] = [:]
  @Published private(set) var played: Set<String> = []
  @Published private(set) var isRefreshing = false
  @Published private(set) var bookmarks: [Bookmark] = []

  private struct Listening: Codable {
    var progress: [String: Double]
    var played: Set<String>
  }

  private let directory: URL = {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
  private var podcastsFile: URL { directory.appendingPathComponent("podcasts.json") }
  private var listeningFile: URL { directory.appendingPathComponent("listening.json") }
  private var bookmarksFile: URL { directory.appendingPathComponent("bookmarks.json") }

  init() {
    if let data = try? Data(contentsOf: podcastsFile),
      let saved = try? JSONDecoder().decode([Podcast].self, from: data)
    {
      podcasts = saved
    }
    if let data = try? Data(contentsOf: listeningFile),
      let saved = try? JSONDecoder().decode(Listening.self, from: data)
    {
      progress = saved.progress
      played = saved.played
    }
    if let data = try? Data(contentsOf: bookmarksFile),
      let saved = try? JSONDecoder().decode([Bookmark].self, from: data)
    {
      bookmarks = saved
    }
  }

  // MARK: - Queries

  func podcast(id: String) -> Podcast? {
    podcasts.first { $0.id == id }
  }

  func episode(id: String) -> Episode? {
    for podcast in podcasts {
      if let episode = podcast.episodes.first(where: { $0.id == id }) { return episode }
    }
    return nil
  }

  /// Newest unplayed episodes across all shows.
  var upNext: [Episode] {
    podcasts.flatMap { $0.episodes.prefix(5) }
      .filter { !played.contains($0.id) }
      .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
  }

  /// In-progress episodes, most progressed first.
  var inProgress: [Episode] {
    podcasts.flatMap(\.episodes).filter {
      (progress[$0.id] ?? 0) > 30 && !played.contains($0.id)
    }
  }

  /// The next unplayed episode in the same show (feeds list newest first, so this moves to newer).
  func episode(after episode: Episode) -> Episode? {
    guard let podcast = podcast(id: episode.podcastID),
      let index = podcast.episodes.firstIndex(where: { $0.id == episode.id })
    else { return upNext.first { $0.id != episode.id } }
    let newer = podcast.episodes[..<index].reversed()
    return newer.first { !played.contains($0.id) }
      ?? upNext.first { $0.id != episode.id }
  }

  func remaining(for episode: Episode) -> TimeInterval? {
    guard let duration = episode.duration, duration > 0 else { return nil }
    return max(duration - (progress[episode.id] ?? 0), 0)
  }

  // MARK: - Subscriptions

  @discardableResult
  func subscribe(feedURL: URL) async throws -> Podcast {
    if let existing = podcast(id: feedURL.absoluteString) { return existing }
    let podcast = try await fetch(feedURL: feedURL)
    podcasts.append(podcast)
    podcasts.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    savePodcasts()
    return podcast
  }

  func unsubscribe(_ podcast: Podcast) {
    podcasts.removeAll { $0.id == podcast.id }
    savePodcasts()
  }

  func refresh(_ podcast: Podcast) async {
    guard let updated = try? await fetch(feedURL: podcast.feedURL),
      let index = podcasts.firstIndex(where: { $0.id == podcast.id })
    else { return }
    podcasts[index] = updated
    savePodcasts()
  }

  func refreshAll() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    await withTaskGroup(of: Void.self) { group in
      for podcast in podcasts {
        group.addTask { await self.refresh(podcast) }
      }
    }
  }

  func refreshIfStale() async {
    let stale = podcasts.contains { ($0.lastRefreshed ?? .distantPast) < Date().addingTimeInterval(-3600) }
    if stale { await refreshAll() }
  }

  func search(_ term: String) async throws -> [PodcastSearchResult] {
    var components = URLComponents(string: "https://itunes.apple.com/search")!
    components.queryItems = [
      .init(name: "media", value: "podcast"), .init(name: "entity", value: "podcast"),
      .init(name: "limit", value: "25"), .init(name: "term", value: term),
    ]
    struct Response: Decodable { let results: [PodcastSearchResult] }
    let (data, _) = try await URLSession.shared.data(from: components.url!)
    return try JSONDecoder().decode(Response.self, from: data).results.filter { $0.feedUrl != nil }
  }

  private nonisolated func fetch(feedURL: URL) async throws -> Podcast {
    var request = URLRequest(url: feedURL)
    request.setValue("CuffTag/1.0", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: request)
    guard let feed = RSSParser.parse(data), !feed.items.isEmpty else {
      throw PodcastError.invalidFeed
    }
    let podcastID = feedURL.absoluteString
    let episodes = feed.items.compactMap { item -> Episode? in
      guard let audio = item.audioURL else { return nil }
      return Episode(
        id: item.guid?.isEmpty == false ? item.guid! : audio.absoluteString,
        title: item.title,
        podcastTitle: feed.title,
        podcastID: podcastID,
        publishedAt: item.pubDate,
        audioURL: audio,
        duration: item.duration,
        summary: item.summary,
        artworkURL: item.imageURL ?? feed.artworkURL)
    }.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    return Podcast(
      feedURL: feedURL, title: feed.title, author: feed.author, artworkURL: feed.artworkURL,
      episodes: episodes, lastRefreshed: Date())
  }

  // MARK: - Listening state

  func setProgress(_ seconds: Double, for episode: Episode) {
    progress[episode.id] = seconds
    saveListening()
  }

  func setPlayed(_ isPlayed: Bool, for episode: Episode) {
    if isPlayed {
      played.insert(episode.id)
      progress[episode.id] = nil
    } else {
      played.remove(episode.id)
    }
    saveListening()
  }

  // MARK: - Bookmarks

  @discardableResult
  func addBookmark(_ episode: Episode, at seconds: Double) -> Bookmark {
    let bookmark = Bookmark(
      episodeID: episode.id, episodeTitle: episode.title, podcastTitle: episode.podcastTitle,
      artworkURL: episode.artworkURL, seconds: seconds)
    bookmarks.insert(bookmark, at: 0)
    saveBookmarks()
    return bookmark
  }

  func removeBookmark(_ bookmark: Bookmark) {
    bookmarks.removeAll { $0.id == bookmark.id }
    saveBookmarks()
  }

  private func saveBookmarks() {
    if let data = try? JSONEncoder().encode(bookmarks) {
      try? data.write(to: bookmarksFile, options: .atomic)
    }
  }

  private func savePodcasts() {
    if let data = try? JSONEncoder().encode(podcasts) {
      try? data.write(to: podcastsFile, options: .atomic)
    }
  }

  private func saveListening() {
    if let data = try? JSONEncoder().encode(Listening(progress: progress, played: played)) {
      try? data.write(to: listeningFile, options: .atomic)
    }
  }
}
