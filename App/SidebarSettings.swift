import Foundation
import Observation

/// What the person chose for the sidebar of one Base: favorite files and folders, and folder icons. Kept on this
/// Mac, per Base, so nothing is written into the Base's files.
@MainActor @Observable
final class SidebarSettings {
    /// Paths relative to the Base, in the order they were added.
    private(set) var favorites: [String] = []
    /// Folder path to the icon's asset name.
    private(set) var folderIcons: [String: String] = [:]
    @ObservationIgnored private var key: String?

    private struct Stored: Codable {
        var favorites: [String] = []
        var folderIcons: [String: String] = [:]
    }

    func load(for root: URL) {
        // A folder's URL may or may not end in "/"; the key shouldn't depend on it.
        var path = root.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        key = "sidebar:" + path
        let stored =
            key.flatMap { UserDefaults.standard.data(forKey: $0) }
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        favorites = stored.favorites
        folderIcons = stored.folderIcons
    }

    func isFavorite(_ path: String) -> Bool { favorites.contains(path) }

    func toggleFavorite(_ path: String) {
        if let index = favorites.firstIndex(of: path) {
            favorites.remove(at: index)
        } else {
            favorites.append(path)
        }
        save()
    }

    /// Nil, or the default folder icon, goes back to the default.
    func setIcon(_ icon: String?, forFolder path: String) {
        folderIcons[path] = icon == FileIcons.folder ? nil : icon
        save()
    }

    /// Keeps a renamed file's favorite.
    func pathMoved(from old: String, to new: String) {
        guard let index = favorites.firstIndex(of: old) else { return }
        favorites[index] = new
        save()
    }

    func pathRemoved(_ path: String) {
        guard favorites.contains(path) else { return }
        favorites.removeAll { $0 == path }
        save()
    }

    private func save() {
        guard let key, let data = try? JSONEncoder().encode(Stored(favorites: favorites, folderIcons: folderIcons))
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
