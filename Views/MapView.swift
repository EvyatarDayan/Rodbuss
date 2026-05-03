//
//  MapView.swift
//  Rödbuss
//
//  Map with current location and nearby bus stations (from SL sites cache).
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Location manager

private final class LocationManager: NSObject, ObservableObject {
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

extension LocationManager: CLLocationManagerDelegate {
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

// MARK: - Map view (map + nearby stops)

struct MapView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var injectedStore = InjectedSearchStore.shared
    @StateObject private var locationManager = LocationManager()
    @State private var isCacheLoading = true
    @State private var nearbySites: [SLSite] = []
    @State private var showSearchNowPrompt = false
    @State private var showStopActions = false
    @State private var selectedStopForActions: SLSite?
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686),
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
    )
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var hasCenteredOnUser = false

    private static let stockholmCenter = CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686)
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    private static let maxNearbyStops = 220
    private static let maxDistanceMeters: CLLocationDistance = 2000
    private static let regionPaddingFactor = 1.15
    private static let minRegionDeltaForRecompute = 0.001
    /// Hide stop markers when zoomed too far out (street-level detail no longer visible).
    private static let maxStopMarkerLatitudeDelta: CLLocationDegrees = 0.035

    private var mapRegion: MKCoordinateRegion {
        let center: CLLocationCoordinate2D
        let span = Self.defaultSpan
        if let loc = locationManager.location {
            center = loc.coordinate
        } else {
            center = Self.stockholmCenter
        }
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea(.all)
                if isCacheLoading {
                    loadingView
                } else {
                    mapView
                }
            }
            .navigationTitle(L10n.string("tab.map", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await loadData() }
            .onAppear(perform: handleOnAppear)
            .onChange(of: locationManager.location) { _, _ in
                if !hasCenteredOnUser, let coord = locationManager.location?.coordinate {
                    let region = MKCoordinateRegion(center: coord, span: Self.defaultSpan)
                    mapPosition = .region(region)
                    visibleRegion = region
                    hasCenteredOnUser = true
                }
                computeNearbySites()
            }
            .overlay(alignment: .bottom) { locationDeniedOverlay }
            .confirmationDialog(L10n.string("map.searchNowPromptTitle", language: currentLanguage), isPresented: $showSearchNowPrompt) {
                Button(L10n.string("map.searchNow", language: currentLanguage)) {
                    InjectedSearchStore.shared.requestSearchNow()
                }
                Button(L10n.string("settings.cancel", language: currentLanguage), role: .cancel) { }
            } message: {
                Text(L10n.string("map.searchNowPromptMessageFormat", language: currentLanguage, injectedStore.injectedOrigin?.name ?? "?", injectedStore.injectedDestination?.name ?? "?"))
            }
            .sheet(isPresented: $showStopActions) {
                VStack(spacing: 14) {
                    Text(selectedStopForActions?.name ?? L10n.string("common.destination", language: currentLanguage))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 8)

                    Button(L10n.string("map.injectToFrom", language: currentLanguage)) {
                        guard let site = selectedStopForActions else { return }
                        InjectedSearchStore.shared.injectOrigin(site)
                        showStopActions = false
                        if InjectedSearchStore.shared.hasBothInjected {
                            showSearchNowPrompt = true
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: UIColor { tc in
                        tc.userInterfaceStyle == .dark
                            ? UIColor.white.withAlphaComponent(0.14)
                            : UIColor.systemGray5
                    }))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(uiColor: UIColor { tc in
                                tc.userInterfaceStyle == .dark
                                    ? UIColor.white.withAlphaComponent(0.25)
                                    : UIColor.systemGray3
                            }), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Button(L10n.string("map.injectToTo", language: currentLanguage)) {
                        guard let site = selectedStopForActions else { return }
                        InjectedSearchStore.shared.injectDestination(site)
                        showStopActions = false
                        if InjectedSearchStore.shared.hasBothInjected {
                            showSearchNowPrompt = true
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: UIColor { tc in
                        tc.userInterfaceStyle == .dark
                            ? UIColor.white.withAlphaComponent(0.14)
                            : UIColor.systemGray5
                    }))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(uiColor: UIColor { tc in
                                tc.userInterfaceStyle == .dark
                                    ? UIColor.white.withAlphaComponent(0.25)
                                    : UIColor.systemGray3
                            }), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Button(L10n.string("settings.cancel", language: currentLanguage), role: .cancel) {
                        showStopActions = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("map.loadingMap", language: currentLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapView: some View {
        Map(position: $mapPosition) {
            mapMarkers
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            guard shouldRecomputeSites(for: context.region) else { return }
            visibleRegion = context.region
            computeNearbySites(region: context.region)
        }
    }

    @MapContentBuilder
    private var mapMarkers: some MapContent {
        if let loc = locationManager.location {
            Marker(L10n.string("map.currentLocation", language: currentLanguage), coordinate: loc.coordinate)
                .tint(.blue)
        }
        if shouldShowStopMarkers {
            ForEach(nearbySites, id: \.id) { site in
                busStopMarker(site: site)
            }
        }
    }

    private var shouldShowStopMarkers: Bool {
        let delta = (visibleRegion ?? mapRegion).span.latitudeDelta
        return delta <= Self.maxStopMarkerLatitudeDelta
    }

    @MapContentBuilder
    private func busStopMarker(site: SLSite) -> some MapContent {
        if let siteLat = site.lat, let siteLon = site.lon {
            let coord = CLLocationCoordinate2D(latitude: siteLat, longitude: siteLon)
            Annotation(site.name, coordinate: coord) {
                Button {
                    selectedStopForActions = site
                    showStopActions = true
                } label: {
                    Image("bus-stop")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                        .padding(8)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var locationDeniedOverlay: some View {
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            Text(L10n.string("map.locationDenied", language: currentLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 24)
        }
    }

    private func handleOnAppear() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            if let loc = locationManager.location?.coordinate {
                let region = MKCoordinateRegion(center: loc, span: Self.defaultSpan)
                mapPosition = .region(region)
                visibleRegion = region
                hasCenteredOnUser = true
            }
        }
    }

    private func loadData() async {
        isCacheLoading = true
        defer { isCacheLoading = false }
        do {
            try await SitesCache.shared.ensureLoaded()
            await MainActor.run {
                let region = visibleRegion ?? mapRegion
                visibleRegion = region
                computeNearbySites(region: region)
            }
        } catch {
            await MainActor.run { nearbySites = [] }
        }
    }

    private func shouldRecomputeSites(for region: MKCoordinateRegion) -> Bool {
        guard let last = visibleRegion else { return true }
        let latChanged = abs(last.center.latitude - region.center.latitude)
        let lonChanged = abs(last.center.longitude - region.center.longitude)
        let latDeltaChanged = abs(last.span.latitudeDelta - region.span.latitudeDelta)
        let lonDeltaChanged = abs(last.span.longitudeDelta - region.span.longitudeDelta)
        return latChanged > Self.minRegionDeltaForRecompute
            || lonChanged > Self.minRegionDeltaForRecompute
            || latDeltaChanged > Self.minRegionDeltaForRecompute
            || lonDeltaChanged > Self.minRegionDeltaForRecompute
    }

    private func computeNearbySites(region: MKCoordinateRegion? = nil) {
        let sites = SitesCache.shared.sites
        let withCoords = sites.filter { $0.lat != nil && $0.lon != nil && $0.hasBus }
        guard !withCoords.isEmpty else {
            nearbySites = []
            return
        }

        if let region {
            let latPadding = region.span.latitudeDelta * 0.5 * (Self.regionPaddingFactor - 1)
            let lonPadding = region.span.longitudeDelta * 0.5 * (Self.regionPaddingFactor - 1)
            let minLat = region.center.latitude - region.span.latitudeDelta / 2 - latPadding
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2 + latPadding
            let minLon = region.center.longitude - region.span.longitudeDelta / 2 - lonPadding
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2 + lonPadding
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            nearbySites = withCoords
                .filter { site in
                    guard let lat = site.lat, let lon = site.lon else { return false }
                    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
                }
                .map { site in
                    let coord = CLLocation(latitude: site.lat!, longitude: site.lon!)
                    return (site, center.distance(from: coord))
                }
                .sorted { $0.1 < $1.1 }
                .prefix(Self.maxNearbyStops)
                .map(\.0)
            return
        }

        let userLocation = locationManager.location
        if let user = userLocation {
            let sorted = withCoords
                .map { site -> (SLSite, CLLocationDistance) in
                    let coord = CLLocation(latitude: site.lat!, longitude: site.lon!)
                    return (site, user.distance(from: coord))
                }
                .filter { $0.1 <= Self.maxDistanceMeters }
                .sorted { $0.1 < $1.1 }
                .prefix(Self.maxNearbyStops)
                .map(\.0)
            nearbySites = Array(sorted)
        } else {
            let stockholm = CLLocation(latitude: Self.stockholmCenter.latitude, longitude: Self.stockholmCenter.longitude)
            let sorted = withCoords
                .map { site -> (SLSite, CLLocationDistance) in
                    let coord = CLLocation(latitude: site.lat!, longitude: site.lon!)
                    return (site, stockholm.distance(from: coord))
                }
                .sorted { $0.1 < $1.1 }
                .prefix(Self.maxNearbyStops)
                .map(\.0)
            nearbySites = Array(sorted)
        }
    }
}

// MARK: - App colors (match Dashboard / My Rides)
private extension Color {
    static let appRed = Color(red: 230/255, green: 79/255, blue: 88/255)
}

#Preview {
    MapView()
        .environment(\.currentLanguage, "English")
}
