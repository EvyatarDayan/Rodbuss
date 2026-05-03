//
//  MyRidesView.swift
//  Rödbuss
//
//  List of saved rides (route + line). Tap to see live departures.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

struct MyRidesView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var store = MyRidesStore.shared
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared
    @State private var isRefreshing = false
    @State private var refreshTimerCancellable: AnyCancellable?
    @State private var mapRideId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView(
                        L10n.string("myRides.emptyTitle", language: currentLanguage),
                        systemImage: "bus",
                        description: Text(L10n.string("myRides.emptySubtitle", language: currentLanguage))
                    )
                } else {
                    ridesList
                }
            }
            .navigationTitle(L10n.string("myRides.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshAllNextDepartures() }
                    } label: {
                        Image("update")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .opacity(isRefreshing ? 0.4 : 1)
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel(L10n.string("map.busRefresh", language: currentLanguage))
                }
            }
            .sheet(isPresented: Binding(
                get: { mapRideId != nil },
                set: { if !$0 { mapRideId = nil } }
            )) {
                if let id = mapRideId, let ride = store.rides.first(where: { $0.id == id }) {
                    RideMapModalView(ride: ride, upcomingDeparture: store.cachedNextDepartures[ride.id])
                }
            }
            .task(id: store.rides.count) {
                if !store.rides.isEmpty, store.loadedRideIds.isEmpty {
                    await refreshAllNextDepartures()
                }
            }
            .onAppear {
                refreshTimerCancellable = Timer.publish(every: 10, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        guard !apiSleepManager.isSleeping else { return }
                        Task { await refreshAllNextDepartures() }
                    }
            }
            .onDisappear {
                refreshTimerCancellable?.cancel()
                refreshTimerCancellable = nil
            }
            .onChange(of: store.rides.count) { _, _ in
                Task { await refreshAllNextDepartures() }
            }
            .onChange(of: apiSleepManager.isSleeping) { _, isSleeping in
                if !isSleeping {
                    Task { await refreshAllNextDepartures() }
                }
            }
        }
    }

    private var ridesList: some View {
        List {
            ForEach(store.rides) { ride in
                myRideCard(ride: ride)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
            }
            .onMove(perform: store.move(fromOffsets:toOffset:))
            .onDelete { store.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .listRowSpacing(10)
        .refreshable {
            await refreshAllNextDepartures()
        }
    }

    private let myRideRowHeight: CGFloat = 88

    private let savedRideDestinationMaxChars = 22

    /// Same source as `BusDepartureRow` / dashboard: headsign (`lineDirectionName`), else destination stop; capped at `savedRideDestinationMaxChars` (ellipsis when trimmed).
    private func savedRideDestinationDisplay(_ ride: SavedRide) -> String {
        let direction = ride.lineDirectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = !direction.isEmpty ? direction : (ride.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if base.isEmpty { return "—" }
        let max = savedRideDestinationMaxChars
        if base.count <= max { return base }
        let keep = max - 1
        guard keep > 0 else { return String(base.prefix(max)) }
        return String(base.prefix(keep)) + "…"
    }

    /// e.g. `in 4 min` → `In 4 min` for the combined one-line display (English-style prefix only).
    private func myRideTimeCountdownHeadline(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("in ") {
            return "In " + String(t.dropFirst(3))
        }
        return s
    }

    /// Single line: `In 4 min (14:34)`, `No information (--:--)`, etc.
    private func myRideSingleLineTimeText(displayTimeTill: String, departureHour: String) -> String {
        let head = myRideTimeCountdownHeadline(displayTimeTill)
        let clock = departureHour.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--:--" : departureHour
        return "\(head) (\(clock))"
    }

    private static let liveClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    @ViewBuilder
    private func myRideCard(ride: SavedRide) -> some View {
        let dep = store.cachedNextDepartures[ride.id]
        let loaded = store.loadedRideIds.contains(ride.id)
        let isCancelled = dep.map { NextDepartureSummary.isCancelled($0) } ?? false
        let timeText = dep.map { NextDepartureSummary.timeTillArrival($0) } ?? "—"
        let minutesOptional = dep.flatMap { NextDepartureSummary.minutesTillArrival($0) }
        let timeNorm = timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        /// Live departure in ~0 minutes (not “unknown time”).
        let isNow = !isCancelled && dep != nil && (
            minutesOptional == 0
            || timeNorm == "nu" || timeNorm == "now"
            || timeNorm == "0 min"
        )
        let noTimeInfo = !isCancelled && !isNow && (dep == nil || timeText == "—")
        let displayTimeTill: String = {
            if isCancelled { return L10n.string("common.cancelled", language: currentLanguage) }
            if noTimeInfo { return L10n.string("myRides.noInformation", language: currentLanguage) }
            if isNow { return L10n.string("time.now", language: currentLanguage) }
            return "in \(timeText)"
        }()
        let departureHour: String = {
            if noTimeInfo { return "--:--" }
            if isNow { return "" }
            return dep.map { NextDepartureSummary.expectedTime($0) } ?? "--:--"
        }()
        let isUrgent = (dep.flatMap { NextDepartureSummary.minutesTillArrival($0) } ?? 99) <= 2
        let hasDep = dep != nil
        let lineColor: Color = {
            guard loaded else { return Color.secondary }
            if isCancelled { return Color.appRed }
            if isNow { return Color.appRed }
            if noTimeInfo { return Color.secondary }
            guard hasDep else { return Color.secondary }
            return (isUrgent ? Color.appRed : Color.appGreen)
        }()
        let mapTap = { mapRideId = ride.id }
        let isDashboard = store.dashboardRideId == ride.id

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 0) {
                    Image("bus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    LineDesignationBadge(designation: ride.lineDesignation)
                        .padding(.leading, 10)
                }
                Text(savedRideDestinationDisplay(ride))
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                dashboardToggleView(for: ride)
            }
            .frame(maxWidth: .infinity)

            SavedRideRouteTitleRow(ride: ride, centerRouteLine: true)
                .padding(.top, 25)
                .padding(.bottom, 10)

            HStack(alignment: .center) {
                Button(action: mapTap) {
                    Image("map1")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .padding(.top, 25)
                Spacer(minLength: 0)
                Group {
                    if !loaded {
                        Text("…")
                            .font(.system(size: 20, weight: .semibold))
                    } else if isNow {
                        Text(L10n.string("time.now", language: currentLanguage))
                            .font(.system(size: 20, weight: .semibold))
                    } else if noTimeInfo {
                        Text(displayTimeTill)
                            .font(.system(size: 20, weight: .semibold))
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(myRideTimeCountdownHeadline(displayTimeTill))
                                .font(.system(size: 20, weight: .semibold))
                            Text("(\(departureHour))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(loaded ? lineColor : Color.secondary)
                Spacer(minLength: 0)
                Color.clear
                    .frame(width: 22, height: 22)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: myRideRowHeight)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .background {
            // Opaque base so shadows render; semi-transparent green alone would make the shadow vanish.
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                if isDashboard {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appGreen.opacity(0.12))
                }
            }
            .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
    }

    private func dashboardToggleView(for ride: SavedRide) -> some View {
        let isSelected = store.dashboardRideId == ride.id
        let toggleFavorite = {
            if isSelected {
                store.setDashboardRide(nil)
            } else {
                store.setDashboardRide(ride.id)
            }
        }
        return HStack(spacing: 2) {
            Button(action: toggleFavorite) {
                Text(L10n.string("myRides.dashboard", language: currentLanguage))
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.appGreen : .secondary)
            }
            .buttonStyle(.plain)
            Button(action: toggleFavorite) {
                Image("star2")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.appGreen : .secondary)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, -4)
    }

    private func refreshAllNextDepartures() async {
        if await !ApiSleepManager.isApiAllowed() { return }
        await MainActor.run { isRefreshing = true }
        var updates: [UUID: SLDeparture] = [:]
        for ride in store.rides {
            if let first = await fetchNextDeparture(for: ride) {
                updates[ride.id] = first
            }
        }
        await MainActor.run {
            store.setCachedNextDepartures(updates, loadedIds: Set(store.rides.map(\.id)))
            isRefreshing = false
        }
    }

    private func fetchNextDeparture(for ride: SavedRide) async -> SLDeparture? {
        do {
            let response = try await SLTransportService.shared.fetchDepartures(siteId: ride.originSiteId)
            var list = response.departures.filter { ($0.line?.transport_mode ?? "").uppercased() == "BUS" }
            if let line = ride.lineDesignation, !line.isEmpty {
                list = list.filter { (($0.line?.designation ?? "").lowercased() == line.lowercased()) }
            }
            if let dir = ride.lineDirectionName, !dir.isEmpty {
                let d = dir.lowercased()
                list = list.filter {
                    ($0.destination?.lowercased().contains(d) ?? false) ||
                    ($0.direction?.lowercased().contains(d) ?? false)
                }
            }
            if let dest = ride.destinationName, !dest.isEmpty {
                let d = dest.lowercased()
                let toDest = list.filter {
                    ($0.destination?.lowercased().contains(d) ?? false) ||
                    ($0.direction?.lowercased().contains(d) ?? false)
                }
                if !toDest.isEmpty {
                    list = toDest
                }
            }
            return list.first
        } catch {
            return nil
        }
    }
}

// MARK: - Next departure time summary (e.g. "14:32" and "3 min")

enum NextDepartureSummary {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static func expectedTime(_ dep: SLDeparture) -> String {
        if let date = dep.expectedDate ?? dep.scheduledDate {
            return timeFormatter.string(from: date)
        }
        if let display = dep.display, display.contains(":"), display.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil {
            return display
        }
        if let display = dep.display, let min = parseMinutes(display) {
            let date = Date().addingTimeInterval(TimeInterval(min * 60))
            return timeFormatter.string(from: date)
        }
        return "—"
    }

    static func timeTillArrival(_ dep: SLDeparture) -> String {
        if let display = dep.display, !display.isEmpty, !(display.contains(":") && display.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil) {
            return display
        }
        guard let date = dep.expectedDate ?? dep.scheduledDate else { return "—" }
        let minutes = Int(date.timeIntervalSince(Date()) / 60)
        if minutes < 0 { return "—" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m) min" : "\(h)h"
    }

    static func isCancelled(_ dep: SLDeparture) -> Bool {
        let state = (dep.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state.contains("cancel") || state.contains("inst") { return true }
        let display = (dep.display ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return display.contains("cancel") || display.contains("inst")
    }

    /// Minutes until departure; nil if unknown. Used for urgent styling (e.g. ≤ 2 min).
    static func minutesTillArrival(_ dep: SLDeparture) -> Int? {
        if let display = dep.display, !display.isEmpty, !(display.contains(":") && display.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil),
           let min = parseMinutes(display) {
            return min
        }
        guard let date = dep.expectedDate ?? dep.scheduledDate else { return nil }
        let minutes = Int(date.timeIntervalSince(Date()) / 60)
        return minutes >= 0 ? minutes : nil
    }

    /// Seconds until departure; nil if unknown. Used for 10-second ring segments.
    static func secondsTillArrival(_ dep: SLDeparture) -> Int? {
        secondsTillArrival(dep, now: Date())
    }

    /// Seconds until departure from a given reference time (e.g. TimelineView context.date).
    static func secondsTillArrival(_ dep: SLDeparture, now: Date) -> Int? {
        if let display = dep.display, !display.isEmpty, !(display.contains(":") && display.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil),
           let min = parseMinutes(display) {
            return min * 60
        }
        guard let date = dep.expectedDate ?? dep.scheduledDate else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        return seconds >= 0 ? seconds : nil
    }

    private static func parseMinutes(_ display: String) -> Int? {
        let t = display.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("min") {
            return Int(t.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if t.hasSuffix("h") || t.hasSuffix("hour") || t.hasSuffix("hours") {
            if let h = Int(t.filter { $0.isNumber }) { return h * 60 }
        }
        return nil
    }
}

// MARK: - Ride map modal (route path + bus position when available)

struct RideMapModalView: View {
    let ride: SavedRide
    let upcomingDeparture: SLDeparture?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @AppStorage("trafiklabApiKey") private var trafiklabApiKey: String = ""
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared
    @State private var busPosition: CLLocationCoordinate2D?
    @State private var secondaryBusStartPositions: [CLLocationCoordinate2D] = []
    @State private var secondaryBusPositions: [CLLocationCoordinate2D] = []
    @State private var secondaryBusStartDistance: CLLocationDistance?
    @State private var secondaryBusTargetDistance: CLLocationDistance?
    @State private var primaryBusTripId: String?
    @State private var secondaryBusTripId: String?
    @State private var secondaryAnimationStartTime: Date?
    @State private var busTargetPosition: CLLocationCoordinate2D?
    /// Animation along route: distance from start of polyline (meters). Used for smooth route-following.
    @State private var busDistanceAlongRoute: Double = 0
    @State private var targetDistanceAlongRoute: Double = 0
    @State private var routeAnimationStartDistance: Double = 0
    @State private var routeAnimationStartTime: Date?
    /// When route has fewer than 2 points we animate in a straight line from this to busTargetPosition.
    @State private var busLinearStartPosition: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeStops: [SLSite] = []
    @State private var busStatus: BusStatus = .noKey
    @State private var busErrorMessage: String?
    @State private var refreshTask: Task<Void, Never>?
    enum BusStatus { case noKey, loading, live, error }
    /// Approximate distance to show bus before origin stop (~one stop).
    private static let preOriginDisplayDistanceMeters: CLLocationDistance = 450
    /// Strict-to-relaxed tolerances used when matching stops to the selected route polyline.
    private static let routeStopToleranceTiers: [CLLocationDistance] = [55, 75, 95]
    private static let routeStopDuplicateMergeDistanceMeters: CLLocationDistance = 35
    private static let routeStopMaxCount = 40

    private var originSite: SLSite? {
        SitesCache.shared.sites.first { $0.id == ride.originSiteId }
    }

    private var destinationSite: SLSite? {
        guard let id = ride.destinationSiteId else { return nil }
        return SitesCache.shared.sites.first { $0.id == id }
    }

    private var originCoordinate: CLLocationCoordinate2D? {
        guard let site = originSite, let lat = site.lat, let lon = site.lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        guard let site = destinationSite, let lat = site.lat, let lon = site.lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var mapRegion: MKCoordinateRegion? {
        var coords = routeCoordinates.isEmpty ? (originCoordinate.map { [$0] } ?? []) + (destinationCoordinate.map { [$0] } ?? []) : routeCoordinates
        if let bus = busPosition { coords.append(bus) }
        coords.append(contentsOf: secondaryBusPositions)
        coords.append(contentsOf: routeStops.compactMap { site in
            guard let lat = site.lat, let lon = site.lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        })
        if coords.isEmpty { return nil }
        if coords.count == 1 {
            return MKCoordinateRegion(center: coords[0], span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.008),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.008)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Route used for bus projection/animation; extends one stop before origin so approaching buses can be shown.
    private var busAnimationRoute: [CLLocationCoordinate2D] {
        Self.extendedRouteBeforeOrigin(routeCoordinates, meters: Self.preOriginDisplayDistanceMeters)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let region = mapRegion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        let animatedBusPosition = currentAnimatedBusPosition(at: context.date)
                        Map(initialPosition: .region(region)) {
                            if let origin = originCoordinate {
                                Annotation(ride.originName, coordinate: origin) {
                                    Image("mapOrigin")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 40, height: 40)
                                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                                        .padding(.bottom, 40)
                                        .padding(.trailing, 10)
                                }
                            }
                            if let dest = destinationCoordinate {
                                Annotation(ride.destinationName ?? L10n.string("common.destination", language: currentLanguage), coordinate: dest) {
                                    Image("mapDestination")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 40, height: 40)
                                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                                        .padding(.bottom, 46)
                                        .padding(.leading, 27)
                                }
                            }
                            if !routeCoordinates.isEmpty {
                                MapPolyline(coordinates: routeCoordinates)
                                    .stroke(.black, lineWidth: 5)
                            } else if let origin = originCoordinate, let dest = destinationCoordinate {
                                MapPolyline(coordinates: [origin, dest])
                                    .stroke(.black, lineWidth: 5)
                            }
                            ForEach(routeStops, id: \.id) { stop in
                                if let lat = stop.lat, let lon = stop.lon {
                                    let stopCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                    Annotation(stop.name, coordinate: stopCoord) {
                                        Image("bus-stop")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 26, height: 26)
                                    }
                                }
                            }
                            if let bus = animatedBusPosition {
                                Annotation("", coordinate: bus) {
                                    ZStack {
                                        Image("bus")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 35, height: 35)
                                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                        Text(ride.lineDesignation ?? "?")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.bottom, 8)
                                    }
                                    .zIndex(1000)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .id(busTargetPosition != nil)
                    .onAppear {
                        fetchRouteAndPosition()
                        startBusPositionRefreshLoop()
                    }
                    .onDisappear {
                        refreshTask?.cancel()
                        refreshTask = nil
                    }
                    .onChange(of: apiSleepManager.isSleeping) { _, isSleeping in
                        if !isSleeping {
                            Task { await refreshBusPosition() }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        L10n.string("map.unavailable", language: currentLanguage),
                        systemImage: "map",
                        description: Text(L10n.string("map.unavailableDescription", language: currentLanguage))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SavedRideRouteTitleRow(ride: ride, titleFont: .system(size: 15, weight: .bold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var hasApiKey: Bool {
        !trafiklabApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fetches route shape (transit or walking) and live bus position.
    private func fetchRouteAndPosition() {
        if let o = originCoordinate, let d = destinationCoordinate {
            routeCoordinates = [o, d]
            routeStops = stopsOnRoute([o, d])
            Task {
                if let coords = await fetchRouteShape(from: o, to: d) {
                    await MainActor.run {
                        routeCoordinates = coords
                        routeStops = stopsOnRoute(coords)
                    }
                }
            }
        } else if let o = originCoordinate {
            routeCoordinates = [o]
            routeStops = []
        }
        Task { await refreshBusPosition() }
    }

    /// Bus stops close to the displayed route polyline, excluding origin/destination stops.
    private func stopsOnRoute(_ route: [CLLocationCoordinate2D]) -> [SLSite] {
        guard route.count >= 2 else { return [] }
        let excludeIds = Set([ride.originSiteId, ride.destinationSiteId].compactMap { $0 })
        let all = SitesCache.shared.sites
            .filter { !excludeIds.contains($0.id) && $0.hasBus && $0.lat != nil && $0.lon != nil }
        let projectedStops: [(site: SLSite, along: CLLocationDistance, offRoute: CLLocationDistance)] = all.compactMap { site in
            guard let lat = site.lat, let lon = site.lon else { return nil }
            let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            guard let projection = Self.projectPoint(point, onto: route) else { return nil }
            let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let projectedLoc = CLLocation(latitude: projection.point.latitude, longitude: projection.point.longitude)
            let offRouteDistance = pointLoc.distance(from: projectedLoc)
            return (site, projection.distance, offRouteDistance)
        }

        guard !projectedStops.isEmpty else { return [] }
        let routeLength = Self.routeLength(route) ?? 0
        let minimumTargetStops = max(2, min(10, Int(routeLength / 550)))
        var selectedTolerance = Self.routeStopToleranceTiers[0]
        var selectedCount = 0
        for tolerance in Self.routeStopToleranceTiers {
            let count = projectedStops.filter { $0.offRoute <= tolerance }.count
            if count >= minimumTargetStops {
                selectedTolerance = tolerance
                selectedCount = count
                break
            }
            if count > selectedCount {
                selectedTolerance = tolerance
                selectedCount = count
            }
        }

        let strictMatches = projectedStops
            .filter { $0.offRoute <= selectedTolerance }
            .sorted { lhs, rhs in
                if abs(lhs.along - rhs.along) < 1 { return lhs.offRoute < rhs.offRoute }
                return lhs.along < rhs.along
            }
        var deduplicated: [(site: SLSite, along: CLLocationDistance, offRoute: CLLocationDistance)] = []
        for candidate in strictMatches {
            guard let lat = candidate.site.lat, let lon = candidate.site.lon else { continue }
            let candidateLoc = CLLocation(latitude: lat, longitude: lon)
            let isDuplicate = deduplicated.contains { existing in
                guard let eLat = existing.site.lat, let eLon = existing.site.lon else { return false }
                let existingLoc = CLLocation(latitude: eLat, longitude: eLon)
                // Merge stop-area duplicates and near-identical named points on same route section.
                if existing.site.name.caseInsensitiveCompare(candidate.site.name) == .orderedSame,
                   abs(existing.along - candidate.along) < 70 {
                    return true
                }
                return existingLoc.distance(from: candidateLoc) <= Self.routeStopDuplicateMergeDistanceMeters
            }
            if !isDuplicate {
                deduplicated.append(candidate)
            }
            if deduplicated.count >= Self.routeStopMaxCount {
                break
            }
        }
        return deduplicated.map(\.site)
    }

    /// Uses MKDirections to get the actual route path (transit if available, else walking).
    private func fetchRouteShape(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D]? {
        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        let destItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        for transportType in [MKDirectionsTransportType.transit, MKDirectionsTransportType.walking] {
            let request = MKDirections.Request()
            request.source = sourceItem
            request.destination = destItem
            request.transportType = transportType
            request.requestsAlternateRoutes = false
            let directions = MKDirections(request: request)
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<[CLLocationCoordinate2D]?, Never>) in
                directions.calculate { response, error in
                    if let route = response?.routes.first, route.polyline.pointCount > 0 {
                        let coords = Self.coordinates(from: route.polyline)
                        continuation.resume(returning: coords.isEmpty ? nil : coords)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let coords = result, !coords.isEmpty { return coords }
        }
        return nil
    }

    private static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }

    private func startBusPositionRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                let cycleStart = Date()
                await refreshBusPosition()
                // Keep a steady 1s cadence including network time.
                let elapsed = Date().timeIntervalSince(cycleStart)
                let remaining = max(0.0, Self.busInterpolationDuration - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
            }
        }
    }

    /// Duration over which we interpolate from current to new API target.
    /// Slightly below refresh cadence so motion doesn't "settle" and pause.
    private static let busInterpolationDuration: TimeInterval = 0.85

    /// Current bus position for the given time (used by TimelineView for smooth 60fps animation along the route).
    private func currentAnimatedBusPosition(at date: Date) -> CLLocationCoordinate2D? {
        guard let target = busTargetPosition else { return nil }
        let route = busAnimationRoute
        let t0 = routeAnimationStartTime ?? date
        let elapsed = date.timeIntervalSince(t0)
        let progress = min(1.0, elapsed / Self.busInterpolationDuration)
        let eased = progress * progress * (3 - 2 * progress)
        if route.count >= 2, let totalLength = Self.routeLength(route), totalLength > 0 {
            let distance = routeAnimationStartDistance + (targetDistanceAlongRoute - routeAnimationStartDistance) * eased
            let clamped = max(0, min(totalLength, distance))
            return Self.pointOnRoute(route, atDistance: clamped) ?? target
        }
        let start = busLinearStartPosition ?? target
        let lat = start.latitude + (target.latitude - start.latitude) * eased
        let lon = start.longitude + (target.longitude - start.longitude) * eased
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Same smoothing animation for secondary buses as the primary bus.
    private func currentAnimatedSecondaryBusPositions(at date: Date) -> [CLLocationCoordinate2D] {
        guard !secondaryBusPositions.isEmpty else { return [] }
        let t0 = secondaryAnimationStartTime ?? date
        let elapsed = date.timeIntervalSince(t0)
        let progress = min(1.0, elapsed / Self.busInterpolationDuration)
        let eased = progress * progress * (3 - 2 * progress)
        let route = busAnimationRoute
        if route.count >= 2,
           let startDistance = secondaryBusStartDistance,
           let targetDistance = secondaryBusTargetDistance,
           let totalLength = Self.routeLength(route),
           totalLength > 0 {
            let distance = startDistance + (targetDistance - startDistance) * eased
            let clamped = max(0, min(totalLength, distance))
            if let snapped = Self.pointOnRoute(route, atDistance: clamped) {
                return [snapped]
            }
        }
        return secondaryBusPositions.enumerated().map { index, target in
            let start = index < secondaryBusStartPositions.count ? secondaryBusStartPositions[index] : target
            let lat = start.latitude + (target.latitude - start.latitude) * eased
            let lon = start.longitude + (target.longitude - start.longitude) * eased
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    /// Current primary-bus distance along route for a given time, if route projection is available.
    private func currentAnimatedDistanceAlongRoute(at date: Date, route: [CLLocationCoordinate2D]) -> CLLocationDistance? {
        guard route.count >= 2, let pos = currentAnimatedBusPosition(at: date) else { return nil }
        return Self.projectPoint(pos, onto: route)?.distance
    }

    /// Adds one virtual segment before the first point, following the inverse of the first route segment.
    private static func extendedRouteBeforeOrigin(_ route: [CLLocationCoordinate2D], meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard route.count >= 2, meters > 0 else { return route }
        guard let extraStart = pointBeforeFirstSegment(route, distance: meters) else { return route }
        return [extraStart] + route
    }

    /// Point located `distance` meters before route[0], opposite to segment route[0] -> route[1].
    private static func pointBeforeFirstSegment(_ route: [CLLocationCoordinate2D], distance: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard route.count >= 2, distance > 0 else { return nil }
        let first = route[0]
        let second = route[1]
        let firstLoc = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let secondLoc = CLLocation(latitude: second.latitude, longitude: second.longitude)
        let segLen = firstLoc.distance(from: secondLoc)
        guard segLen > 0 else { return nil }
        let ratio = min(1.0, distance / segLen)
        let lat = first.latitude + (first.latitude - second.latitude) * ratio
        let lon = first.longitude + (first.longitude - second.longitude) * ratio
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Total length of the route polyline in meters.
    private static func routeLength(_ route: [CLLocationCoordinate2D]) -> CLLocationDistance? {
        guard route.count >= 2 else { return nil }
        var total: CLLocationDistance = 0
        for i in 0..<(route.count - 1) {
            let a = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            let b = CLLocation(latitude: route[i + 1].latitude, longitude: route[i + 1].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    /// Project a point onto the route polyline; returns distance from start (meters) and closest point.
    private static func projectPoint(_ point: CLLocationCoordinate2D, onto route: [CLLocationCoordinate2D]) -> (distance: CLLocationDistance, point: CLLocationCoordinate2D)? {
        guard route.count >= 2 else { return nil }
        let loc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let routeLocs = route.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var bestDist = CLLocationDistance.infinity
        var bestDistanceAlong: CLLocationDistance = 0
        var bestPoint = route[0]
        var accumulated: CLLocationDistance = 0
        for i in 0..<(routeLocs.count - 1) {
            let (segDist, t) = distanceFromPointToSegment(loc, segment: (routeLocs[i], routeLocs[i + 1]))
            if segDist < bestDist {
                bestDist = segDist
                let a = route[i], b = route[i + 1]
                bestPoint = CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
                let segLength = routeLocs[i].distance(from: routeLocs[i + 1])
                bestDistanceAlong = accumulated + t * segLength
            }
            accumulated += routeLocs[i].distance(from: routeLocs[i + 1])
        }
        return (bestDistanceAlong, bestPoint)
    }

    /// Distance from point to segment; returns (distance, t) where t is 0..1 along segment.
    private static func distanceFromPointToSegment(_ point: CLLocation, segment: (CLLocation, CLLocation)) -> (CLLocationDistance, Double) {
        let (a, b) = segment
        let ax = a.coordinate.longitude, ay = a.coordinate.latitude
        let bx = b.coordinate.longitude, by = b.coordinate.latitude
        let px = point.coordinate.longitude, py = point.coordinate.latitude
        let abx = bx - ax, aby = by - ay
        let apx = px - ax, apy = py - ay
        let segLenSq = abx * abx + aby * aby
        var t: Double = 0.5
        if segLenSq > 0 { t = max(0, min(1, (apx * abx + apy * aby) / segLenSq)) }
        let qx = ax + t * abx, qy = ay + t * aby
        let q = CLLocation(latitude: qy, longitude: qx)
        return (point.distance(from: q), t)
    }

    /// Point on the route at the given distance from the start (meters).
    private static func pointOnRoute(_ route: [CLLocationCoordinate2D], atDistance distance: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard route.count >= 2, distance >= 0 else { return route.first }
        var accumulated: CLLocationDistance = 0
        for i in 0..<(route.count - 1) {
            let a = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            let b = CLLocation(latitude: route[i + 1].latitude, longitude: route[i + 1].longitude)
            let segLen = a.distance(from: b)
            if distance <= accumulated + segLen {
                let t = segLen > 0 ? (distance - accumulated) / segLen : 0
                let tClamped = max(0, min(1, t))
                return CLLocationCoordinate2D(
                    latitude: route[i].latitude + (route[i + 1].latitude - route[i].latitude) * tClamped,
                    longitude: route[i].longitude + (route[i + 1].longitude - route[i].longitude) * tClamped
                )
            }
            accumulated += segLen
        }
        return route.last
    }

    /// Returns up to maxCount positions closest to the route polyline; uses first positions when route is empty.
    private static func positionsClosestToRoute(_ positions: [VehiclePositionItem], route: [CLLocationCoordinate2D], maxCount: Int) -> [VehiclePositionItem] {
        guard maxCount > 0, !positions.isEmpty else { return [] }
        guard route.count >= 2 else { return Array(positions.prefix(maxCount)) }
        let routeLocations = route.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let sorted = positions.sorted { a, b in
            let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
            var da = CLLocationDistance.infinity
            var db = CLLocationDistance.infinity
            for i in 0..<(routeLocations.count - 1) {
                let seg = (routeLocations[i], routeLocations[i + 1])
                da = min(da, distanceFromPoint(la, toSegment: seg))
                db = min(db, distanceFromPoint(lb, toSegment: seg))
            }
            return da < db
        }
        return Array(sorted.prefix(maxCount))
    }

    private static func normalizedTripId(_ tripId: String?) -> String? {
        guard let tripId else { return nil }
        let t = tripId.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func distance(_ item: VehiclePositionItem, to coord: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: item.latitude, longitude: item.longitude)
        let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return a.distance(from: b)
    }

    /// Stable selection for max two buses:
    /// 1) keep previous trip IDs when present,
    /// 2) otherwise keep nearest to previous coordinates,
    /// 3) then fallback to closest-to-route ranking.
    private static func selectStableBuses(
        _ positions: [VehiclePositionItem],
        route: [CLLocationCoordinate2D],
        previousPrimaryTripId: String?,
        previousPrimaryCoord: CLLocationCoordinate2D?,
        previousSecondaryTripId: String?,
        previousSecondaryCoord: CLLocationCoordinate2D?
    ) -> (primary: VehiclePositionItem?, secondary: VehiclePositionItem?) {
        let ranked = positionsClosestToRoute(positions, route: route, maxCount: positions.count)
        guard !ranked.isEmpty else { return (nil, nil) }
        var usedIndices: Set<Int> = []

        func pick(preferredTripId: String?, preferredCoord: CLLocationCoordinate2D?) -> VehiclePositionItem? {
            if let tripId = normalizedTripId(preferredTripId),
               let idx = ranked.firstIndex(where: { normalizedTripId($0.tripId) == tripId }),
               !usedIndices.contains(idx) {
                usedIndices.insert(idx)
                return ranked[idx]
            }
            if let coord = preferredCoord {
                let available = ranked.enumerated().filter { !usedIndices.contains($0.offset) }
                if let nearest = available.min(by: { distance($0.element, to: coord) < distance($1.element, to: coord) }) {
                    let d = distance(nearest.element, to: coord)
                    // Keep identity only when bus stayed reasonably close between refreshes.
                    if d <= 300 {
                        usedIndices.insert(nearest.offset)
                        return nearest.element
                    }
                }
            }
            if let first = ranked.enumerated().first(where: { !usedIndices.contains($0.offset) }) {
                usedIndices.insert(first.offset)
                return first.element
            }
            return nil
        }

        let primary = pick(preferredTripId: previousPrimaryTripId, preferredCoord: previousPrimaryCoord)
        let secondary = pick(preferredTripId: previousSecondaryTripId, preferredCoord: previousSecondaryCoord)
        return (primary, secondary)
    }

    private static func distanceFromPoint(_ point: CLLocation, toSegment segment: (CLLocation, CLLocation)) -> CLLocationDistance {
        let (a, b) = segment
        let ax = a.coordinate.longitude, ay = a.coordinate.latitude
        let bx = b.coordinate.longitude, by = b.coordinate.latitude
        let px = point.coordinate.longitude, py = point.coordinate.latitude
        let abx = bx - ax, aby = by - ay
        let apx = px - ax, apy = py - ay
        let segLenSq = abx * abx + aby * aby
        var t: Double = 0
        if segLenSq > 0 { t = max(0, min(1, (apx * abx + apy * aby) / segLenSq)) }
        let qx = ax + t * abx, qy = ay + t * aby
        let q = CLLocation(latitude: qy, longitude: qx)
        return point.distance(from: q)
    }

    private func refreshBusPosition() async {
        if await !ApiSleepManager.isApiAllowed() { return }
        let key = trafiklabApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            busStatus = hasApiKey ? .loading : .noKey
            busErrorMessage = nil
        }
        let lineFilter = ride.lineDesignation?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let tripIdFilter = upcomingDeparture?.journey?.id.map(String.init)
            let positions = try await BusPositionService.shared.fetchVehiclePositions(
                apiKey: key,
                lineFilter: lineFilter,
                directionFilter: ride.lineDirectionId,
                tripIdFilter: tripIdFilter
            )
            let (route, previousPrimaryCoord, previousSecondaryCoord, previousPrimaryTrip, previousSecondaryTrip) = await MainActor.run {
                let now = Date()
                return (
                    busAnimationRoute,
                    currentAnimatedBusPosition(at: now) ?? busTargetPosition,
                    currentAnimatedSecondaryBusPositions(at: now).first,
                    primaryBusTripId,
                    secondaryBusTripId
                )
            }
            let selected = Self.selectStableBuses(
                positions,
                route: route,
                previousPrimaryTripId: previousPrimaryTrip,
                previousPrimaryCoord: previousPrimaryCoord,
                previousSecondaryTripId: previousSecondaryTrip,
                previousSecondaryCoord: previousSecondaryCoord
            )
            await MainActor.run {
                if let primary = selected.primary {
                    let c = CLLocationCoordinate2D(latitude: primary.latitude, longitude: primary.longitude)
                    let route = busAnimationRoute
                    let now = Date()
                    let currentAnimated = currentAnimatedBusPosition(at: now)
                    let currentDist = currentAnimatedDistanceAlongRoute(at: now, route: route)
                    busTargetPosition = c
                    primaryBusTripId = Self.normalizedTripId(primary.tripId)
                    // Keep only one bus visible: the one matching selected direction/path.
                    secondaryBusStartDistance = nil
                    secondaryBusTargetDistance = nil
                    secondaryBusStartPositions = []
                    secondaryBusPositions = []
                    secondaryBusTripId = nil
                    secondaryAnimationStartTime = nil
                    if route.count >= 2, let totalLength = Self.routeLength(route), totalLength > 0,
                       let projected = Self.projectPoint(c, onto: route) {
                        if let d = currentDist {
                            routeAnimationStartDistance = d
                        } else {
                            routeAnimationStartDistance = projected.distance
                        }
                        targetDistanceAlongRoute = projected.distance
                        busDistanceAlongRoute = projected.distance
                        routeAnimationStartTime = now
                    } else {
                        routeAnimationStartDistance = 0
                        targetDistanceAlongRoute = 0
                        busLinearStartPosition = currentAnimated ?? busPosition ?? c
                        routeAnimationStartTime = now
                    }
                    busPosition = currentAnimated ?? c
                    busStatus = .live
                } else {
                    busTargetPosition = nil
                    busPosition = nil
                    secondaryBusStartDistance = nil
                    secondaryBusTargetDistance = nil
                    secondaryBusStartPositions = []
                    secondaryBusPositions = []
                    primaryBusTripId = nil
                    secondaryBusTripId = nil
                    secondaryAnimationStartTime = nil
                    busLinearStartPosition = nil
                    routeAnimationStartTime = nil
                    busStatus = hasApiKey ? .error : .noKey
                }
                busErrorMessage = nil
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                busTargetPosition = nil
                busPosition = nil
                secondaryBusStartDistance = nil
                secondaryBusTargetDistance = nil
                secondaryBusStartPositions = []
                secondaryBusPositions = []
                primaryBusTripId = nil
                secondaryBusTripId = nil
                secondaryAnimationStartTime = nil
                busLinearStartPosition = nil
                routeAnimationStartTime = nil
                busStatus = hasApiKey ? .error : .noKey
                busErrorMessage = message
            }
        }
    }
}

// MARK: - Location manager for ride map (user position)

private final class RideMapLocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension RideMapLocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

// MARK: - App colors

private extension Color {
    static let appGreen = Color(red: 20/255, green: 182/255, blue: 90/255)   // #14b65a
    static let appRed = Color(red: 230/255, green: 79/255, blue: 88/255)       // #e64f58
}

#Preview {
    NavigationStack {
        MyRidesView()
    }
}
