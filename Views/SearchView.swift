//
//  SearchView.swift
//  Rödbuss
//
//  Search: origin & destination (cached sites), then see bus departures.
//  Last search and results are persisted and restored when the app reopens.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

private enum FromToSearchField: String, Identifiable {
    case from, to
    var id: String { rawValue }
}

private struct LastSearchState: Codable {
    var origin: SLSite?
    var destination: SLSite?
    var departures: [SLDeparture]
}

private enum LastSearchStore {
    static let key = "lastSearchState"

    static func load() -> LastSearchState? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(LastSearchState.self, from: data) else { return nil }
        return state
    }

    static func save(origin: SLSite?, destination: SLSite?, departures: [SLDeparture]) {
        let state = LastSearchState(origin: origin, destination: destination, departures: departures)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct SearchView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @State private var isCacheLoading = true
    @State private var cacheError: String?

    // Origin / destination search
    @State private var origin: SLSite?
    @State private var destination: SLSite?
    @State private var originSearch = ""
    @State private var destinationSearch = ""
    @State private var searchResults: [SLDeparture] = []
    /// Displayed result rows; fixed until user taps Search again (avoids reordering on selection).
    @State private var displayedSearchResults: [SLDeparture] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showDuplicateRideAlert = false
    @State private var showRideSavedAlert = false
    @State private var rideSavedPopupMessageKey = "rideSaved.savedToMyRides"
    @State private var dontShowRideSavedAgain = false
    @State private var saveUiRefreshTick: Int = 0
    @State private var stopPickerTarget: FromToSearchField?
    @AppStorage("searchHideRideSavedPopup") private var hideRideSavedPopup = false

    /// True after the user has tapped Search at least once (so we can show empty state).
    @State private var searchHasBeenRun = false

    /// Staggered reveal (same motion as dashboard/favorite); cap keeps long lists snappy.
    @State private var visibleSearchResultCount = 0
    @State private var searchResultsListExiting = false
    @State private var revealTask: Task<Void, Never>?

    private static let searchResultsRevealCap = 15
    private static let searchResultsListMaxRows = 30

    @FocusState private var focusedSearchField: FromToSearchField?

    private var sites: [SLSite] { SitesCache.shared.sites }

    private var filteredOriginSites: [SLSite] {
        prioritizedSitesForField(query: originSearch, forDestination: false)
    }

    private var filteredDestinationSites: [SLSite] {
        prioritizedSitesForField(query: destinationSearch, forDestination: true)
    }

    private func filterSites(_ list: [SLSite], by query: String) -> [SLSite] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(list.prefix(50)) }
        return list.filter { $0.name.lowercased().contains(q) }.prefix(50).map { $0 }
    }

    /// Sort matches so exact match is first, then "starts with" query, then "contains". Within each group, sort by name.
    private func sortMatchesByRelevance(_ matches: [SLSite], query: String) -> [SLSite] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(matches) }
        return matches.sorted { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            let aExact = aName == q
            let bExact = bName == q
            if aExact != bExact { return aExact }
            let aStarts = aName.hasPrefix(q)
            let bStarts = bName.hasPrefix(q)
            if aStarts != bStarts { return aStarts }
            return aName.localizedCompare(bName) == .orderedAscending
        }
    }

    /// When query is empty, put last-used (from LastSearchStore) first; otherwise return matches sorted by relevance (exact first).
    private func prioritizedSitesForField(query: String, forDestination: Bool) -> [SLSite] {
        let matches = filterSites(sites, by: query)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            return sortMatchesByRelevance(Array(matches), query: q)
        }
        guard let state = LastSearchStore.load() else { return Array(matches) }
        let first = forDestination ? state.destination : state.origin
        let second = forDestination ? state.origin : state.destination
        var ordered: [SLSite] = []
        if let f = first, let inList = sites.first(where: { $0.id == f.id }) {
            ordered.append(inList)
        }
        if let s = second, s.id != first?.id, let inList = sites.first(where: { $0.id == s.id }), !ordered.contains(where: { $0.id == inList.id }) {
            ordered.append(inList)
        }
        let orderedIds = Set(ordered.map(\.id))
        ordered += matches.filter { !orderedIds.contains($0.id) }
        return Array(ordered.prefix(50))
    }

    /// One row per (line, destination), sorted by date. Call when search results are set to keep list stable.
    private func computeDisplayedResults(from departures: [SLDeparture]) -> [SLDeparture] {
        let grouped = Dictionary(grouping: departures) { dep in
            "\(dep.line?.designation ?? "")|\(dep.destination ?? dep.direction ?? "")"
        }
        let keys = grouped.keys.sorted()
        let onePerGroup = keys.compactMap { key -> SLDeparture? in
            grouped[key]?.min { a, b in
                let da = a.expectedDate ?? a.scheduledDate ?? .distantFuture
                let db = b.expectedDate ?? b.scheduledDate ?? .distantFuture
                return da < db
            }
        }
        return onePerGroup.sorted { a, b in
            let da = a.expectedDate ?? a.scheduledDate ?? .distantFuture
            let db = b.expectedDate ?? b.scheduledDate ?? .distantFuture
            return da < db
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.string("search.title", language: currentLanguage))
                        .font(.headline)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await loadCache() }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
            .alert(L10n.string("rideExists.title", language: currentLanguage), isPresented: $showDuplicateRideAlert) {
                Button(L10n.string("common.ok", language: currentLanguage), role: .cancel) { }
            } message: {
                Text(L10n.string("rideExists.message", language: currentLanguage))
            }
            .sheet(isPresented: $showRideSavedAlert, onDismiss: { dontShowRideSavedAgain = false }) {
                VStack(spacing: 14) {
                    Text(L10n.string(rideSavedPopupMessageKey, language: currentLanguage))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Button {
                        dontShowRideSavedAgain.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: dontShowRideSavedAgain ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(dontShowRideSavedAgain ? Color(red: 20/255, green: 182/255, blue: 90/255) : .secondary)
                            Text(L10n.string("rideSaved.dontShowAgain", language: currentLanguage))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)

                    Button(L10n.string("common.ok", language: currentLanguage)) {
                        if dontShowRideSavedAgain { hideRideSavedPopup = true }
                        showRideSavedAlert = false
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.gray.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    )

                    Button(L10n.string("tab.myRides", language: currentLanguage)) {
                        if dontShowRideSavedAgain { hideRideSavedPopup = true }
                        showRideSavedAlert = false
                        InjectedSearchStore.shared.requestMyRides()
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.gray.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $stopPickerTarget) { target in
                SearchStopPickerMapView(targetField: target) { site, selectedField in
                    switch selectedField {
                    case .from:
                        origin = site
                        originSearch = site.name
                    case .to:
                        destination = site
                        destinationSearch = site.name
                    }
                    searchHasBeenRun = false
                    focusedSearchField = nil
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isCacheLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.string("search.loadingStops", language: currentLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = cacheError {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.string("common.retry", language: currentLanguage)) {
                    Task { await loadCache() }
                }
            }
            
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea(.all)
                VStack(alignment: .leading, spacing: 20) {
                    fromToCard
                    showDeparturesButton
                        .padding(.top, 6)
                    if let err = searchError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 0)
                    }
                    Rectangle()
                        .fill(Color(.gray))
                        .frame(height: 2)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    searchResultsSection
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

                suggestionsOverlay
            }
        }
    }

    @ViewBuilder
    private var suggestionsOverlay: some View {
        if origin == nil && (focusedSearchField == .from || !originSearch.isEmpty) && !filteredOriginSites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 148)
                suggestionsList(sites: filteredOriginSites) { site in
                    origin = site
                    originSearch = site.name
                    focusedSearchField = nil
                    searchHasBeenRun = false
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .zIndex(1)
        } else if destination == nil && (focusedSearchField == .to || !destinationSearch.isEmpty) && !filteredDestinationSites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 148)
                suggestionsList(sites: filteredDestinationSites) { site in
                    destination = site
                    destinationSearch = site.name
                    focusedSearchField = nil
                    searchHasBeenRun = false
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .zIndex(1)
        }
    }

    private func suggestionsList(sites: [SLSite], onSelect: @escaping (SLSite) -> Void) -> some View {
        let list = Array(sites.prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, site in
                Button {
                    onSelect(site)
                } label: {
                    HStack {
                        Text(site.name)
                            .foregroundStyle(.primary)
                        if let abbr = site.abbreviation, !abbr.isEmpty {
                            Text(abbr)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                if index < list.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(searchCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private static let mintGreen = Color(red: 0.56, green: 0.83, blue: 0.73)
    private static let mintGreenDark = Color(red: 0.45, green: 0.75, blue: 0.65)

    private var searchCardBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
        })
    }

    private var fromToCard: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 0) {
                originFieldContent
                    .padding(.bottom, 5)
                Divider()
                    .padding(.bottom, 2)
                    .background(Color(.gray))
                    .padding(.horizontal, 0)
                    .padding(.bottom, 5)
                destinationFieldContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.vertical, 15)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            Button {
                stopPickerTarget = .from
                focusedSearchField = nil
            } label: {
                Image("map1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
//                    .frame(width: 30, height: 30)
//                    .background(Color(red: 20/255, green: 182/255, blue: 90/255).opacity(0.2))
//                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 60)
            .padding(.top, 12)
        }
        .overlay(alignment: .trailing) {
            Button {
                swapOriginAndDestination()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 45, height: 45)
                    .background(Color(.darkGray))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 70)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(searchCardBackground)
                .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
    }

    private let fromToRowHeight: CGFloat = 56
    private let fromToLabelHeight: CGFloat = 16
    private var fromToContentHeight: CGFloat { fromToRowHeight - fromToLabelHeight - 4 }

    @ViewBuilder
    private var originFieldContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("search.from", language: currentLanguage))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(height: fromToLabelHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let o = origin {
                    HStack(spacing: 6) {
                        Text(o.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let abbr = o.abbreviation, !abbr.isEmpty {
                            Text(abbr)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    SiteSearchField(
                        search: $originSearch,
                        placeholder: L10n.string("search.selectOrigin", language: currentLanguage),
                        suggestions: filteredOriginSites
                    ) { site in
                        origin = site
                        originSearch = site.name
                        searchHasBeenRun = false
                    }
                    .frame(maxWidth: .infinity)
                    .focused($focusedSearchField, equals: .from)
                }
                Button {
                    origin = nil
                    originSearch = ""
                    searchHasBeenRun = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(origin != nil || !originSearch.isEmpty ? Color(.systemGray3) : Color(.systemGray4))
                }
                .disabled(origin == nil && originSearch.isEmpty)
                .buttonStyle(.plain)
            }
            .frame(height: fromToContentHeight)
        }
        .frame(height: fromToRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var destinationFieldContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("search.to", language: currentLanguage))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(height: fromToLabelHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let d = destination {
                    HStack(spacing: 6) {
                        Text(d.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let abbr = d.abbreviation, !abbr.isEmpty {
                            Text(abbr)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    SiteSearchField(
                        search: $destinationSearch,
                        placeholder: L10n.string("search.selectDestination", language: currentLanguage),
                        suggestions: filteredDestinationSites
                    ) { site in
                        destination = site
                        destinationSearch = site.name
                        searchHasBeenRun = false
                    }
                    .frame(maxWidth: .infinity)
                    .focused($focusedSearchField, equals: .to)
                }
                Button {
                    destination = nil
                    destinationSearch = ""
                    searchHasBeenRun = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(destination != nil || !destinationSearch.isEmpty ? Color(.systemGray3) : Color(.systemGray4))
                }
                .disabled(destination == nil && destinationSearch.isEmpty)
                .buttonStyle(.plain)
            }
            .frame(height: fromToContentHeight)
        }
        .frame(height: fromToRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showDeparturesButton: some View {
        Button {
            Task { await searchDepartures() }
        } label: {
            Text(L10n.string("search.searchButton", language: currentLanguage))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 200)
                .frame(height: 56)
        }
        .background(origin == nil || isSearching ? Color.gray : Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(origin == nil || isSearching)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if let o = origin, searchHasBeenRun || isSearching {
            VStack(alignment: .leading, spacing: 12) {
                if let d = destination {
                    HStack(alignment: .center, spacing: 12) {
                        Text(o.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        RouteDottedArrowSeparator()
                            .frame(width: 32, height: 11)
                        Text(d.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 9)
                } else {
                    Text(L10n.string("search.busesFrom", language: currentLanguage, o.name))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 9)
                }
                if isSearching && displayedSearchResults.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.string("search.loading", language: currentLanguage))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 24)
                } else if searchResults.isEmpty && !isSearching {
                    Text(L10n.string("search.noResults", language: currentLanguage))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 24)
                } else {
                    let listRows = Array(displayedSearchResults.prefix(Self.searchResultsListMaxRows))
                    let rowCount = listRows.count
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(listRows.enumerated()), id: \.element.id) { index, dep in
                                let line = dep.line?.designation
                                let directionName = dep.destination ?? dep.direction
                                let directionId = dep.direction_code
                                let isAlreadySaved = line.map { _ in
                                    _ = saveUiRefreshTick
                                    return MyRidesStore.shared.containsRide(
                                        originSiteId: o.id,
                                        destinationSiteId: destination?.id,
                                        lineDesignation: line,
                                        lineDirectionId: directionId,
                                        lineDirectionName: directionName
                                    )
                                } ?? false
                                HStack(spacing: 12) {
                                    BusDepartureRow(departure: dep, showTime: false)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        let defaultName = (dep.destination ?? dep.direction ?? "")
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        if isAlreadySaved {
                                            if removeFromMyRides(for: dep) {
                                                saveUiRefreshTick &+= 1
                                                rideSavedPopupMessageKey = "rideSaved.removedFromMyRides"
                                                if !hideRideSavedPopup {
                                                    showRideSavedAlert = true
                                                }
                                            }
                                        } else {
                                            if performSaveToMyRides(for: dep, customName: defaultName.isEmpty ? nil : defaultName) {
                                                saveUiRefreshTick &+= 1
                                                rideSavedPopupMessageKey = "rideSaved.savedToMyRides"
                                                if !hideRideSavedPopup {
                                                    showRideSavedAlert = true
                                                }
                                            } else {
                                                showDuplicateRideAlert = true
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isAlreadySaved {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            Text(isAlreadySaved ? L10n.string("search.saved", language: currentLanguage) : L10n.string("search.save", language: currentLanguage))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 20/255, green: 182/255, blue: 90/255))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(searchCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .opacity(searchResultRowVisible(index: index, total: rowCount) ? 1 : 0)
                                .scaleEffect(x: searchResultRowVisible(index: index, total: rowCount) ? 1 : 0.9, y: 1, anchor: .leading)
                                .offset(x: searchResultRowVisible(index: index, total: rowCount) ? 0 : -18)
                            }
                        }
                        .opacity(searchResultsListExiting ? 0 : 1)
                        .scaleEffect(x: searchResultsListExiting ? 0.94 : 1, y: 1, anchor: .trailing)
                        .offset(x: searchResultsListExiting ? 22 : 0)
                        .padding(.top, 4)
                        .padding(.bottom, 0)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func searchResultRowVisible(index: Int, total: Int) -> Bool {
        let cap = min(Self.searchResultsRevealCap, total)
        if index < cap {
            return index < visibleSearchResultCount
        }
        return visibleSearchResultCount >= cap
    }

    private func syncSearchResultsVisibleWithoutAnimation() {
        revealTask?.cancel()
        revealTask = nil
        searchResultsListExiting = false
        let n = min(Self.searchResultsListMaxRows, displayedSearchResults.count)
        guard n > 0 else {
            visibleSearchResultCount = 0
            return
        }
        let cap = min(Self.searchResultsRevealCap, n)
        visibleSearchResultCount = n <= cap ? n : cap
    }

    private func animateSearchResultReveal(total: Int) {
        revealTask?.cancel()
        visibleSearchResultCount = 0
        let n = min(Self.searchResultsListMaxRows, total)
        let cap = min(Self.searchResultsRevealCap, n)
        guard cap > 0 else { return }
        revealTask = Task {
            for idx in 1...cap {
                try? await Task.sleep(for: .milliseconds(24))
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        visibleSearchResultCount = idx
                    }
                }
            }
        }
    }

    private func loadCache() async {
        isCacheLoading = true
        cacheError = nil
        defer { isCacheLoading = false }
        do {
            try await SitesCache.shared.ensureLoaded()
            let (injOrigin, injDestination) = InjectedSearchStore.shared.consumeInjected()
            if injOrigin != nil || injDestination != nil {
                if let o = injOrigin {
                    origin = o
                    originSearch = o.name
                }
                if let d = injDestination {
                    destination = d
                    destinationSearch = d.name
                }
            } else {
                restoreLastSearch()
            }
            if InjectedSearchStore.shared.shouldRunSearchOnNextAppear {
                InjectedSearchStore.shared.shouldRunSearchOnNextAppear = false
                await searchDepartures()
            }
        } catch {
            cacheError = error.localizedDescription
        }
    }

    private func restoreLastSearch() {
        guard let state = LastSearchStore.load() else { return }
        origin = state.origin
        destination = state.destination
        if let o = state.origin { originSearch = o.name }
        if let d = state.destination { destinationSearch = d.name }
        searchResults = state.departures
        displayedSearchResults = computeDisplayedResults(from: state.departures)
        searchHasBeenRun = true
        syncSearchResultsVisibleWithoutAnimation()
    }

    private func searchDepartures() async {
        guard let origin = origin else { return }
        let hadContent = await MainActor.run {
            isSearching = true
            searchError = nil
            return !displayedSearchResults.isEmpty
        }
        if !hadContent {
            await MainActor.run {
                searchResults = []
                displayedSearchResults = []
                visibleSearchResultCount = 0
                revealTask?.cancel()
                revealTask = nil
            }
        } else {
            await MainActor.run {
                revealTask?.cancel()
                revealTask = nil
            }
        }
        do {
            let destName = destination?.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var allBuses: [SLDeparture] = []
            let originSitesToTry = sitesToTryForOrigin(origin)
            for site in originSitesToTry {
                let response = try await SLTransportService.shared.fetchDepartures(siteId: site.id)
                let list = response.departures.filter { ($0.line?.transport_mode ?? "").uppercased() == "BUS" }
                if list.isEmpty { continue }
                allBuses = list
                break
            }
            var buses = allBuses
            if let d = destName, !d.isEmpty {
                let filtered = buses.filter { dep in departureMatchesDestination(dep, searchDestinationName: d) }
                if !filtered.isEmpty {
                    buses = filtered
                } else {
                    // If we cannot reliably text-match destination, avoid showing both opposite directions
                    // of the same line; keep the closest upcoming direction per line.
                    buses = reduceToSingleDirectionPerLine(buses)
                }
                // Destination is selected: only one direction per line should be shown.
                buses = reduceToSingleDirectionPerLine(buses)
            }
            let displayed = computeDisplayedResults(from: buses)
            if hadContent {
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.1)) {
                        searchResultsListExiting = true
                    }
                }
                try? await Task.sleep(for: .milliseconds(105))
            }
            await MainActor.run {
                searchResults = buses
                displayedSearchResults = displayed
                searchResultsListExiting = false
                searchError = nil
                visibleSearchResultCount = 0
                LastSearchStore.save(origin: origin, destination: destination, departures: buses)
                isSearching = false
                searchHasBeenRun = true
                if !displayed.isEmpty {
                    animateSearchResultReveal(total: displayed.count)
                }
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                searchResultsListExiting = false
                isSearching = false
                searchHasBeenRun = true
            }
        }
    }

    /// Sites to try for this origin: same name first, then any site whose name contains (or is contained in) the origin name.
    private func sitesToTryForOrigin(_ site: SLSite) -> [SLSite] {
        let name = site.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return [site] }
        let exact = sites.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }
        var candidates = exact
        if candidates.isEmpty {
            candidates = [site]
        }
        let substring = sites.filter { other in
            guard other.id != site.id else { return false }
            let otherName = other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return otherName.contains(name) || name.contains(otherName)
        }
        let seen = Set(candidates.map(\.id))
        let extra = substring.filter { !seen.contains($0.id) }
        let ordered = candidates + extra
        return ordered.sorted { a, b in
            if a.id == site.id { return true }
            if b.id == site.id { return false }
            return a.id < b.id
        }
    }

    /// Match departure destination/direction to search string (bidirectional contains; also match first word so "Drevergatan" matches "Drevergatan, Stockholm").
    private func departureMatchesDestination(_ dep: SLDeparture, searchDestinationName: String) -> Bool {
        let dest = (dep.destination ?? dep.direction ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !dest.isEmpty, !searchDestinationName.isEmpty else { return true }
        if dest.contains(searchDestinationName) || searchDestinationName.contains(dest) { return true }
        let searchFirst = searchDestinationName.split(separator: " ").first.map(String.init) ?? ""
        let destFirst = dest.split(separator: " ").first.map(String.init) ?? ""
        if !searchFirst.isEmpty, searchFirst.count >= 3, dest.contains(searchFirst) || destFirst == searchFirst { return true }
        return false
    }

    /// For each line designation, keep one direction (closest upcoming departure).
    /// Used as fallback when destination text matching fails.
    private func reduceToSingleDirectionPerLine(_ departures: [SLDeparture]) -> [SLDeparture] {
        func normalizedLineKey(_ dep: SLDeparture) -> String {
            let raw = (dep.line?.designation ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let compact = raw.filter { $0.isLetter || $0.isNumber }
            return compact.isEmpty ? raw : compact
        }
        let grouped = Dictionary(grouping: departures) { dep in
            normalizedLineKey(dep)
        }
        let onePerLine = grouped.values.compactMap { deps -> SLDeparture? in
            deps.min { a, b in
                let da = a.expectedDate ?? a.scheduledDate ?? .distantFuture
                let db = b.expectedDate ?? b.scheduledDate ?? .distantFuture
                return da < db
            }
        }
        return onePerLine.sorted { a, b in
            let da = a.expectedDate ?? a.scheduledDate ?? .distantFuture
            let db = b.expectedDate ?? b.scheduledDate ?? .distantFuture
            return da < db
        }
    }

    private func swapOriginAndDestination() {
        let o = origin
        let d = destination
        let oSearch = originSearch
        let dSearch = destinationSearch
        origin = d
        destination = o
        originSearch = dSearch
        destinationSearch = oSearch
    }

    /// Saves a specific search result ride to My Rides. Returns true if saved, false if duplicate.
    private func performSaveToMyRides(for dep: SLDeparture, customName: String?) -> Bool {
        guard let origin = origin, let line = dep.line?.designation else { return false }
        let destId = destination?.id
        if MyRidesStore.shared.containsRide(
            originSiteId: origin.id,
            destinationSiteId: destId,
            lineDesignation: line,
            lineDirectionId: dep.direction_code,
            lineDirectionName: dep.destination ?? dep.direction
        ) {
            return false
        }
        let direction = (dep.destination ?? dep.direction)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        MyRidesStore.shared.add(
            customName: name.isEmpty ? nil : name,
            originName: origin.name,
            originSiteId: origin.id,
            destinationName: destination?.name,
            destinationSiteId: destId,
            lineDesignation: line,
            lineDirectionName: direction?.isEmpty == true ? nil : direction,
            lineDirectionId: dep.direction_code
        )
        return true
    }

    /// Removes a specific saved ride matching the selected search result.
    private func removeFromMyRides(for dep: SLDeparture) -> Bool {
        guard let origin = origin, let line = dep.line?.designation else { return false }
        let destId = destination?.id
        let targetDirectionId = dep.direction_code
        let normalizedDirectionName = (dep.destination ?? dep.direction)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let match = MyRidesStore.shared.rides.first { ride in
            guard ride.originSiteId == origin.id,
                  ride.destinationSiteId == destId,
                  ride.lineDesignation == line else {
                return false
            }
            if let targetId = targetDirectionId {
                return ride.lineDirectionId == targetId
            }
            if let rideId = ride.lineDirectionId {
                return targetDirectionId == rideId
            }
            let rideDirectionName = ride.lineDirectionName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return rideDirectionName == normalizedDirectionName
        }
        guard let match else { return false }
        MyRidesStore.shared.remove(match)
        return true
    }
}

// MARK: - Site search field (suggestions from cached sites)

private final class SearchStopPickerLocationManager: NSObject, ObservableObject {
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
}

extension SearchStopPickerLocationManager: CLLocationManagerDelegate {
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

private struct SearchStopPickerMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @StateObject private var locationManager = SearchStopPickerLocationManager()

    let targetField: FromToSearchField
    let onSelect: (SLSite, FromToSearchField) -> Void

    @State private var isLoading = true
    @State private var nearbySites: [SLSite] = []
    @State private var selectedSite: SLSite?
    @State private var showAddDialog = false
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
    private static let maxStopMarkerLatitudeDelta: CLLocationDegrees = 0.035

    private var mapRegion: MKCoordinateRegion {
        let center = locationManager.location?.coordinate ?? Self.stockholmCenter
        return MKCoordinateRegion(center: center, span: Self.defaultSpan)
    }

    private var navTitle: String {
        switch targetField {
        case .from:
            return L10n.string("search.from", language: currentLanguage)
        case .to:
            return L10n.string("search.to", language: currentLanguage)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.string("map.loadingMap", language: currentLanguage))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Map(position: $mapPosition) {
                        if let user = locationManager.location?.coordinate {
                            Marker(L10n.string("map.currentLocation", language: currentLanguage), coordinate: user)
                                .tint(.blue)
                        }
                        if shouldShowStopMarkers {
                            ForEach(nearbySites, id: \.id) { site in
                                if let lat = site.lat, let lon = site.lon {
                                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                    Annotation(site.name, coordinate: coord) {
                                        Button {
                                            selectedSite = site
                                            showAddDialog = true
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
                        }
                    }
                    .mapStyle(.standard)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        guard shouldRecomputeSites(for: context.region) else { return }
                        visibleRegion = context.region
                        computeNearbySites(region: context.region)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) { dismiss() }
                }
            }
            .task { await loadNearbySites() }
            .onAppear {
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
            .onChange(of: locationManager.location) { _, _ in
                if !hasCenteredOnUser, let coord = locationManager.location?.coordinate {
                    let region = MKCoordinateRegion(center: coord, span: Self.defaultSpan)
                    mapPosition = .region(region)
                    visibleRegion = region
                    hasCenteredOnUser = true
                }
                computeNearbySites(region: visibleRegion ?? mapRegion)
            }
            .sheet(isPresented: $showAddDialog) {
                VStack(spacing: 14) {
                    Text(selectedSite?.name ?? L10n.string("common.destination", language: currentLanguage))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 8)

                    Button(L10n.string("map.injectToFrom", language: currentLanguage)) {
                        guard let site = selectedSite else { return }
                        onSelect(site, .from)
                        dismiss()
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
                        guard let site = selectedSite else { return }
                        onSelect(site, .to)
                        dismiss()
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
                        showAddDialog = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func loadNearbySites() async {
        isLoading = true
        defer { isLoading = false }
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

    private var shouldShowStopMarkers: Bool {
        let delta = (visibleRegion ?? mapRegion).span.latitudeDelta
        return delta <= Self.maxStopMarkerLatitudeDelta
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
        let all = SitesCache.shared.sites.filter { $0.lat != nil && $0.lon != nil && $0.hasBus }
        guard !all.isEmpty else {
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
            nearbySites = all
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
        if let user = locationManager.location {
            nearbySites = all
                .map { site in
                    let coord = CLLocation(latitude: site.lat!, longitude: site.lon!)
                    return (site, user.distance(from: coord))
                }
                .filter { $0.1 <= Self.maxDistanceMeters }
                .sorted { $0.1 < $1.1 }
                .prefix(Self.maxNearbyStops)
                .map(\.0)
        } else {
            let stockholm = CLLocation(latitude: Self.stockholmCenter.latitude, longitude: Self.stockholmCenter.longitude)
            nearbySites = all
                .map { site in
                    let coord = CLLocation(latitude: site.lat!, longitude: site.lon!)
                    return (site, stockholm.distance(from: coord))
                }
                .sorted { $0.1 < $1.1 }
                .prefix(Self.maxNearbyStops)
                .map(\.0)
        }
    }
}

private struct SiteSearchField: View {
    @Binding var search: String
    let placeholder: String
    let suggestions: [SLSite]
    let onSelect: (SLSite) -> Void

    var body: some View {
        TextField(placeholder, text: $search)
            .font(.body)
            .noAutocorrectOrAutocomplete()
            .padding(.horizontal, 0)
            .padding(.vertical, 4)
    }
}

// MARK: - Departures for one stop (bus only)

struct StopDeparturesView: View {
    let site: SLSite
    @State private var departures: [SLDeparture] = []
    @State private var isLoading = true
    @State private var error: String?

    /// Bus-only departures; API returns all modes.
    private var busDepartures: [SLDeparture] {
        departures.filter { ($0.line?.transport_mode ?? "").uppercased() == "BUS" }
    }

    var body: some View {
        stopDeparturesContent
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await fetchDepartures() }
            .refreshable { await fetchDepartures() }
    }

    @ViewBuilder
    private var stopDeparturesContent: some View {
        if isLoading {
            ProgressView("Loading buses…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = error {
            ContentUnavailableView(
                "Couldn't load departures",
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
            .overlay(alignment: .bottom) {
                Button("Retry") {
                    Task { await fetchDepartures() }
                }
                .padding(.bottom, 24)
            }
        } else if busDepartures.isEmpty {
            ContentUnavailableView(
                "No buses",
                systemImage: "bus",
                description: Text("No bus departures at this stop right now.")
            )
        } else {
            List {
                Section("Bus departures") {
                    ForEach(busDepartures.prefix(30)) { dep in
                        BusDepartureRow(departure: dep)
                    }
                }
            }
        }
    }

    private func fetchDepartures() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await SLTransportService.shared.fetchDepartures(siteId: site.id)
            departures = response.departures
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Line badge (matches Find search results)

/// Green rounded line number, same styling as `BusDepartureRow` in Find.
struct LineDesignationBadge: View {
    let designation: String?

    /// Fixed width so short (e.g. `6`) and long (e.g. `203`) lines share the same pill size; text stays centered.
    private static let contentWidth: CGFloat = 44

    private var display: String {
        let t = designation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "—" : t
    }

    var body: some View {
        Text(display)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: Self.contentWidth, alignment: .center)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.green.opacity(0.45), lineWidth: 0.8)
            )
    }
}

// MARK: - Row: line, destination, expected time (14:34), time till arrival (e.g. 12m)

struct BusDepartureRow: View {
    @Environment(\.currentLanguage) private var currentLanguage
    let departure: SLDeparture
    var showTime: Bool = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var expectedTimeText: String {
        if let date = departure.expectedDate ?? departure.scheduledDate {
            return Self.timeFormatter.string(from: date)
        }
        if let display = departure.display, display.contains(":"), display.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil {
            return display
        }
        if let display = departure.display, let minutes = parseMinutesFromDisplay(display) {
            let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
            return Self.timeFormatter.string(from: date)
        }
        return "—"
    }

    private func parseMinutesFromDisplay(_ display: String) -> Int? {
        let trimmed = display.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("min") {
            let num = trimmed.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(num)
        }
        if trimmed.hasSuffix("h") || trimmed.hasSuffix("hour") || trimmed.hasSuffix("hours") {
            let num = trimmed.filter { $0.isNumber }
            if let h = Int(num) { return h * 60 }
        }
        return nil
    }

    private var isDisplayClockTime: Bool {
        guard let d = departure.display, d.contains(":"), d.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return false }
        return true
    }

    private var timeTillArrivalText: String {
        if let display = departure.display, !display.isEmpty, !isDisplayClockTime {
            return display
        }
        guard let date = departure.expectedDate ?? departure.scheduledDate else { return "—" }
        let minutes = Int(date.timeIntervalSince(Date()) / 60)
        if minutes < 0 { return "—" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var minutesTillArrival: Int? {
        if let display = departure.display, !display.isEmpty, !isDisplayClockTime,
           let min = parseMinutesFromDisplay(display) {
            return min
        }
        guard let date = departure.expectedDate ?? departure.scheduledDate else { return nil }
        let minutes = Int(date.timeIntervalSince(Date()) / 60)
        return minutes >= 0 ? minutes : nil
    }

    private var timeTillArrivalDisplayText: String {
        let t = timeTillArrivalText
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "—" {
            return t
        }
        if trimmed.lowercased() == "nu" || trimmed.lowercased() == "now" {
            return L10n.string("time.now", language: currentLanguage)
        }
        return "in \(t)"
    }

    private var destinationDisplayText: String {
        let name = departure.destination ?? departure.direction ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    var body: some View {
        let isUrgent = (minutesTillArrival ?? 99) <= 2
        HStack(alignment: .center, spacing: 12) {
            LineDesignationBadge(designation: departure.line?.designation)

            Text(destinationDisplayText)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showTime {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeTillArrivalDisplayText)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(isUrgent ? .red : .primary)
                    Text(expectedTimeText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - No autocorrect/autocomplete (use on all text fields in this app)

extension View {
    /// Disables autocorrect and autocomplete. Use on every TextField/TextEditor in the app.
    func noAutocorrectOrAutocomplete() -> some View {
        self
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
    }
}

#Preview {
    SearchView()
}
