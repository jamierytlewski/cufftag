import Foundation

struct Podcast: Codable, Identifiable, Hashable {
  var id: String { feedURL.absoluteString }
  var feedURL: URL
  var title: String
  var author: String
  var artworkURL: URL?
  var episodes: [Episode]
  var lastRefreshed: Date?
}

struct Episode: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var podcastTitle: String
  var podcastID: String
  var publishedAt: Date?
  var audioURL: URL
  var duration: TimeInterval?
  var summary: String
  var artworkURL: URL?
}

/// A moment saved from the sleeve while listening.
struct Bookmark: Codable, Identifiable, Hashable {
  var id = UUID()
  var episodeID: String
  var episodeTitle: String
  var podcastTitle: String
  var artworkURL: URL?
  var seconds: Double
  var createdAt = Date()
}

struct PodcastSearchResult: Identifiable, Decodable, Hashable {
  let collectionId: Int
  let collectionName: String
  let artistName: String?
  let feedUrl: URL?
  let artworkUrl600: URL?
  let artworkUrl100: URL?

  var id: Int { collectionId }
  var artwork: URL? { artworkUrl600 ?? artworkUrl100 }
}

/// Minimal RSS/iTunes podcast feed parser.
final class RSSParser: NSObject, XMLParserDelegate {
  struct Feed {
    var title = ""
    var author = ""
    var artworkURL: URL?
    var items: [Item] = []
  }

  struct Item {
    var guid: String?
    var title = ""
    var pubDate: Date?
    var audioURL: URL?
    var duration: TimeInterval?
    var summary = ""
    var imageURL: URL?
  }

  private var feed = Feed()
  private var item: Item?
  private var text = ""
  private var inChannelImage = false

  static func parse(_ data: Data) -> Feed? {
    let delegate = RSSParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() || !delegate.feed.items.isEmpty else { return nil }
    return delegate.feed
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String] = [:]
  ) {
    text = ""
    switch elementName {
    case "item":
      item = Item()
    case "enclosure":
      if let url = attributes["url"].flatMap(URL.init(string:)) {
        let type = attributes["type"] ?? "audio"
        if type.hasPrefix("audio") || type.hasPrefix("video") || item?.audioURL == nil {
          item?.audioURL = url
        }
      }
    case "itunes:image":
      let url = attributes["href"].flatMap(URL.init(string:))
      if item != nil {
        item?.imageURL = url
      } else if feed.artworkURL == nil {
        feed.artworkURL = url
      }
    case "image":
      if item == nil { inChannelImage = true }
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    text += String(decoding: CDATABlock, as: UTF8.self)
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if item != nil {
      switch elementName {
      case "item":
        if let item { feed.items.append(item) }
        self.item = nil
      case "title":
        if item?.title.isEmpty == true { item?.title = value }
      case "guid":
        item?.guid = value
      case "pubDate":
        item?.pubDate = Self.parseDate(value)
      case "itunes:duration":
        item?.duration = Self.parseDuration(value)
      case "description", "itunes:summary", "content:encoded":
        if item?.summary.isEmpty == true { item?.summary = Self.stripHTML(value) }
      default:
        break
      }
    } else {
      switch elementName {
      case "title":
        if !inChannelImage && feed.title.isEmpty { feed.title = value }
      case "itunes:author":
        if feed.author.isEmpty { feed.author = value }
      case "url":
        if inChannelImage && feed.artworkURL == nil { feed.artworkURL = URL(string: value) }
      case "image":
        inChannelImage = false
      default:
        break
      }
    }
    text = ""
  }

  private static let dateFormatters: [DateFormatter] = [
    "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z",
    "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "yyyy-MM-dd'T'HH:mm:ssZ",
  ].map {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = $0
    return formatter
  }

  static func parseDate(_ string: String) -> Date? {
    for formatter in dateFormatters {
      if let date = formatter.date(from: string) { return date }
    }
    return nil
  }

  static func parseDuration(_ string: String) -> TimeInterval? {
    let parts = string.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
  }

  static func stripHTML(_ string: String) -> String {
    string
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
