//
//  SitesCache.swift
//  Rödbuss
//
//  Download /sites once and save locally. Only call /departures live.
//  Stick to the Transport API /sites endpoint to avoid ID conversion issues.
//

import Foundation

/// Persists the full sites list locally. Use as the app’s search index; don’t fetch on every launch.
final class SitesCache {
    static let shared = SitesCache()

    /// How long before we consider the cache stale and refetch in background.
    private let maxAge: TimeInterval = 24 * 60 * 60 // 24 hours

    private let fileManager = FileManager.default
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    private let baseURL = "https://transport.integration.sl.se/v1"
    private var cachedSites: [SLSite]?
    private var lastFetched: Date?

    private var cacheFileURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sl_sites.json")
    }

    private var metaFileURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sl_sites_meta.json")
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// All sites from cache (may be empty until loaded). Prefer `sites` for reading.
    var sites: [SLSite] {
        cachedSites ?? []
    }

    /// Call on app launch. Uses cache if valid; otherwise fetches and saves. Throws only when we have no cache and fetch fails.
    func ensureLoaded() async throws {
        guard await ApiSleepManager.isApiAllowed() else { throw ApiSleepError.sleeping }
        if isCacheValid, !(cachedSites?.isEmpty ?? true) {
            return
        }
        let hadCache = !(cachedSites?.isEmpty ?? true)
        do {
            try await fetchAndSave()
        } catch {
            if !hadCache { throw error }
            // Keep using stale cache; don’t throw
        }
    }

    /// Force refresh (e.g. pull-to-refresh). Fetches and saves. Throws if fetch failed.
    func refresh() async throws {
        guard await ApiSleepManager.isApiAllowed() else { throw ApiSleepError.sleeping }
        try await fetchAndSave()
    }

    /// Clear cached sites from memory and disk. Next ensureLoaded() will refetch.
    func clearCache() {
        cachedSites = nil
        lastFetched = nil
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: metaFileURL)
    }

    /// Resolve a favorite stop name to an SLSite (first match by name, case-insensitive contains).
    func site(forFavoriteName name: String) -> SLSite? {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        return cachedSites?.first { $0.name.lowercased().contains(q) }
    }

    // MARK: - Private

    private var isCacheValid: Bool {
        guard let last = lastFetched else { return false }
        return Date().timeIntervalSince(last) < maxAge
    }

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: cacheFileURL)
            cachedSites = try JSONDecoder().decode([SLSite].self, from: data)
        } catch {
            cachedSites = nil
        }
        do {
            let metaData = try Data(contentsOf: metaFileURL)
            let meta = try JSONDecoder().decode(CacheMeta.self, from: metaData)
            lastFetched = meta.fetchedAt
        } catch {
            lastFetched = nil
        }
    }

    private func fetchAndSave() async throws {
        let url = URL(string: "\(baseURL)/sites?expand=true")!
        let (data, _) = try await session.data(from: url)
        let sites = try JSONDecoder().decode([SLSite].self, from: data)
        cachedSites = sites
        lastFetched = Date()
        try saveToDisk(sites: sites)
    }

    private func saveToDisk(sites: [SLSite]) throws {
        let data = try JSONEncoder().encode(sites)
        try data.write(to: cacheFileURL)
        let meta = CacheMeta(fetchedAt: lastFetched ?? Date())
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaFileURL)
    }
}

private struct CacheMeta: Codable {
    let fetchedAt: Date
}
