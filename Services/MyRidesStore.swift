//
//  MyRidesStore.swift
//  Rödbuss
//
//  Persists saved search results (origin + destination) as "My Rides".
//

import Combine
import Foundation
import SwiftUI

struct SavedRide: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    /// User-defined name shown in My Rides and Dashboard. Nil = show origin (and route details).
    let customName: String?
    let originName: String
    let originSiteId: Int
    let destinationName: String?
    let destinationSiteId: Int?
    /// Line number to show for this route (e.g. "6"). Nil = all lines.
    let lineDesignation: String?
    /// Bus direction/destination for this line (e.g. "Ropsten") so only one direction is shown.
    let lineDirectionName: String?
    /// GTFS direction_id (0 or 1) for this route; used to filter live bus to same direction only. Nil = show all buses on line.
    let lineDirectionId: Int?
    let savedAt: Date

    /// Title to show in list and dashboard: custom name if set and non-empty, otherwise origin.
    var displayName: String {
        let name = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? originName : name
    }

    init(id: UUID = UUID(), customName: String? = nil, originName: String, originSiteId: Int, destinationName: String? = nil, destinationSiteId: Int? = nil, lineDesignation: String? = nil, lineDirectionName: String? = nil, lineDirectionId: Int? = nil, savedAt: Date = Date()) {
        self.id = id
        self.customName = customName
        self.originName = originName
        self.originSiteId = originSiteId
        self.destinationName = destinationName
        self.destinationSiteId = destinationSiteId
        self.lineDesignation = lineDesignation
        self.lineDirectionName = lineDirectionName
        self.lineDirectionId = lineDirectionId
        self.savedAt = savedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, customName, originName, originSiteId, destinationName, destinationSiteId, lineDesignation, lineDirectionName, lineDirectionId, savedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        originName = try c.decode(String.self, forKey: .originName)
        originSiteId = try c.decode(Int.self, forKey: .originSiteId)
        destinationName = try c.decodeIfPresent(String.self, forKey: .destinationName)
        destinationSiteId = try c.decodeIfPresent(Int.self, forKey: .destinationSiteId)
        lineDesignation = try c.decodeIfPresent(String.self, forKey: .lineDesignation)
        lineDirectionName = try c.decodeIfPresent(String.self, forKey: .lineDirectionName)
        lineDirectionId = try c.decodeIfPresent(Int.self, forKey: .lineDirectionId)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
    }
}

final class MyRidesStore: ObservableObject {
    static let shared = MyRidesStore()

    private let key = "myRides"
    private let dashboardKey = "dashboardRideId"

    @Published private(set) var rides: [SavedRide] = []
    @Published var dashboardRideId: UUID?

    /// Cached next departure for the dashboard ride. Persists across tab switches; updated every 10s.
    @Published var dashboardNextDeparture: SLDeparture?

    /// Cached next departures per ride for My Rides list. Persists across tab switches; updated every 10s.
    @Published var cachedNextDepartures: [UUID: SLDeparture] = [:]
    /// Ride ids for which we have attempted a fetch (so we can show "No results" vs loading).
    @Published var loadedRideIds: Set<UUID> = []

    private init() {
        load()
        loadDashboardRideId()
    }

    func setDashboardRide(_ rideId: UUID?) {
        dashboardRideId = rideId
        if rideId == nil { dashboardNextDeparture = nil }
        UserDefaults.standard.set(rideId?.uuidString, forKey: dashboardKey)
    }

    func setDashboardNextDeparture(_ dep: SLDeparture?) {
        dashboardNextDeparture = dep
    }

    func setCachedNextDepartures(_ updates: [UUID: SLDeparture], loadedIds: Set<UUID>) {
        cachedNextDepartures = updates
        loadedRideIds = loadedIds
    }

    private func loadDashboardRideId() {
        guard let s = UserDefaults.standard.string(forKey: dashboardKey),
              let id = UUID(uuidString: s) else { return }
        dashboardRideId = id
    }

    /// Returns true if a ride with the same origin, destination, line and direction already exists.
    func containsRide(originSiteId: Int, destinationSiteId: Int?, lineDesignation: String?, lineDirectionId: Int? = nil, lineDirectionName: String? = nil) -> Bool {
        let normalizedDirectionName = lineDirectionName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return rides.contains { ride in
            guard ride.originSiteId == originSiteId,
                  ride.destinationSiteId == destinationSiteId,
                  ride.lineDesignation == lineDesignation else {
                return false
            }
            // Prefer direction_id match when available, otherwise fallback to destination/direction text.
            if let targetId = lineDirectionId {
                return ride.lineDirectionId == targetId
            }
            if let rideId = ride.lineDirectionId {
                // Current check has no direction id but saved ride has one: treat as different.
                return lineDirectionId == rideId
            }
            let rideDirectionName = ride.lineDirectionName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return rideDirectionName == normalizedDirectionName
        }
    }

    func add(customName: String? = nil, originName: String, originSiteId: Int, destinationName: String? = nil, destinationSiteId: Int? = nil, lineDesignation: String? = nil, lineDirectionName: String? = nil, lineDirectionId: Int? = nil) {
        let ride = SavedRide(
            customName: customName,
            originName: originName,
            originSiteId: originSiteId,
            destinationName: destinationName,
            destinationSiteId: destinationSiteId,
            lineDesignation: lineDesignation,
            lineDirectionName: lineDirectionName,
            lineDirectionId: lineDirectionId
        )
        rides.insert(ride, at: 0)
        save()
    }

    func updateCustomName(rideId: UUID, customName: String?) {
        guard let index = rides.firstIndex(where: { $0.id == rideId }) else { return }
        let existing = rides[index]
        let updated = SavedRide(
            id: existing.id,
            customName: customName,
            originName: existing.originName,
            originSiteId: existing.originSiteId,
            destinationName: existing.destinationName,
            destinationSiteId: existing.destinationSiteId,
            lineDesignation: existing.lineDesignation,
            lineDirectionName: existing.lineDirectionName,
            lineDirectionId: existing.lineDirectionId,
            savedAt: existing.savedAt
        )
        rides[index] = updated
        save()
    }

    func remove(_ ride: SavedRide) {
        if dashboardRideId == ride.id { setDashboardRide(nil) }
        rides.removeAll { $0.id == ride.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        let toRemove = offsets.map { rides[$0].id }
        if let dash = dashboardRideId, toRemove.contains(dash) { setDashboardRide(nil) }
        rides.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        rides.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedRide].self, from: data) else { return }
        rides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
