//
//  InjectedSearchStore.swift
//  Rödbuss
//
//  Holds bus stops injected from the Map (Inject to From / Inject to To).
//  SearchView consumes these when it appears and fills the From/To fields.
//

import Combine
import Foundation

final class InjectedSearchStore: ObservableObject {
    static let shared = InjectedSearchStore()

    @Published private(set) var injectedOrigin: SLSite?
    @Published private(set) var injectedDestination: SLSite?

    /// When true, ContentView should switch to Search tab and then clear this.
    @Published var requestSwitchToSearchAndRun: Bool = false
    /// When true, ContentView should switch to My Rides tab and then clear this.
    @Published var requestSwitchToMyRides: Bool = false
    /// When true, SearchView should run search after consuming injected (and then clear this).
    @Published var shouldRunSearchOnNextAppear: Bool = false

    /// True when both origin and destination have been injected (e.g. from Map). Use to show "Search now" only then.
    var hasBothInjected: Bool { injectedOrigin != nil && injectedDestination != nil }

    private init() {}

    func injectOrigin(_ site: SLSite) {
        injectedOrigin = site
    }

    func injectDestination(_ site: SLSite) {
        injectedDestination = site
    }

    /// Call from Map when user taps "Search now". Switches to Search and runs search when Search appears.
    func requestSearchNow() {
        requestSwitchToSearchAndRun = true
        shouldRunSearchOnNextAppear = true
    }

    func clearRequestSwitchToSearchAndRun() {
        requestSwitchToSearchAndRun = false
    }

    func requestMyRides() {
        requestSwitchToMyRides = true
    }

    func clearRequestSwitchToMyRides() {
        requestSwitchToMyRides = false
    }

    /// Returns any injected origin and destination and clears them. Call from SearchView when it appears.
    func consumeInjected() -> (origin: SLSite?, destination: SLSite?) {
        let result = (injectedOrigin, injectedDestination)
        injectedOrigin = nil
        injectedDestination = nil
        return result
    }
}
