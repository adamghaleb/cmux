import Foundation

/// Manages web favorites and recent URLs for the browser panel.
final class WebFavoritesStore: ObservableObject {
    static let shared = WebFavoritesStore()

    private let favoritesKey = "com.fadicode.web.favorites"
    private let recentsKey = "com.fadicode.web.recents"
    private let maxRecents = 12

    @Published private(set) var favorites: [WebBookmark] = []
    @Published private(set) var recents: [WebBookmark] = []

    private init() {
        favorites = load(key: favoritesKey)
        recents = load(key: recentsKey)
    }

    // MARK: - Favorites

    func addFavorite(url: String, title: String?) {
        let bookmark = WebBookmark(url: url, title: title ?? displayName(for: url))
        guard !favorites.contains(where: { $0.url == url }) else { return }
        favorites.insert(bookmark, at: 0)
        save(favorites, key: favoritesKey)
    }

    func removeFavorite(url: String) {
        favorites.removeAll { $0.url == url }
        save(favorites, key: favoritesKey)
    }

    func isFavorite(url: String) -> Bool {
        favorites.contains { $0.url == url }
    }

    // MARK: - Recents

    func trackVisit(url: String, title: String?) {
        let bookmark = WebBookmark(url: url, title: title ?? displayName(for: url))
        recents.removeAll { $0.url == url }
        recents.insert(bookmark, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        save(recents, key: recentsKey)
    }

    func clearRecents() {
        recents = []
        save(recents, key: recentsKey)
    }

    // MARK: - Helpers

    private func displayName(for urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else { return urlString }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func load(key: String) -> [WebBookmark] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let bookmarks = try? JSONDecoder().decode([WebBookmark].self, from: data) else {
            return []
        }
        return bookmarks
    }

    private func save(_ bookmarks: [WebBookmark], key: String) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct WebBookmark: Codable, Identifiable, Equatable {
    let url: String
    let title: String
    var id: String { url }
}
