import Combine
import SwiftUI

struct DashboardCarouselView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var store = MyRidesStore.shared
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared

    @State private var selectedRideId: UUID?
    @State private var departuresByRideId: [UUID: [SLDeparture]] = [:]
    @State private var loadingRideIds: Set<UUID> = []
    @State private var refreshCancellable: AnyCancellable?
    @State private var pulseCancellable: AnyCancellable?
    @State private var circlePulseOpacity: Double = 1.0
    @State private var showRideMap = false
    @State private var mapRide: SavedRide?
    @State private var visibleDepartureCountByRideId: [UUID: Int] = [:]
    @State private var departuresListExitingByRideId: [UUID: Bool] = [:]
    @State private var revealTasksByRideId: [UUID: Task<Void, Never>] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView(
                        L10n.string("dashboard.emptyTitle", language: currentLanguage),
                        systemImage: "house",
                        description: Text(L10n.string("dashboard.emptySubtitle", language: currentLanguage))
                    )
                } else {
                    TabView(selection: $selectedRideId) {
                        ForEach(store.rides) { ride in
                            ridePage(ride)
                                .tag(Optional(ride.id))
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .animation(.easeInOut(duration: 0.25), value: selectedRideId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                syncSelectedRide()
                startRefreshLoop()
                startPulseLoop()
                if let id = selectedRideId, let ride = store.rides.first(where: { $0.id == id }) {
                    Task { await refreshRide(ride, animateDepartures: false) }
                }
            }
            .onDisappear {
                refreshCancellable?.cancel()
                refreshCancellable = nil
                pulseCancellable?.cancel()
                pulseCancellable = nil
                for task in revealTasksByRideId.values { task.cancel() }
                revealTasksByRideId.removeAll()
            }
            .onChange(of: selectedRideId) { _, newId in
                store.setDashboardRide(newId)
                if let id = newId, let ride = store.rides.first(where: { $0.id == id }) {
                    Task { await refreshRide(ride, animateDepartures: false) }
                }
            }
            .onChange(of: store.rides) { _, _ in
                syncSelectedRide()
            }
            .onChange(of: apiSleepManager.isSleeping) { _, isSleeping in
                if !isSleeping, let id = selectedRideId, let ride = store.rides.first(where: { $0.id == id }) {
                    Task { await refreshRide(ride, animateDepartures: true) }
                }
            }
            .sheet(isPresented: $showRideMap) {
                if let ride = mapRide {
                    RideMapModalView(ride: ride, upcomingDeparture: departuresByRideId[ride.id]?.first)
                }
            }
        }
    }

    @ViewBuilder
    private func ridePage(_ ride: SavedRide) -> some View {
        VStack(alignment: .center, spacing: 28) {
            SavedRideRouteTitleRow(ride: ride, centerRouteLine: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

            ZStack {
                timeToDepartureCircle(ride)
                HStack {
                    carouselNavButton(systemName: "chevron.left", enabled: canNavigateRide(by: -1)) {
                        navigateRide(by: -1)
                    }
                    Spacer()
                    carouselNavButton(systemName: "chevron.right", enabled: canNavigateRide(by: 1)) {
                        navigateRide(by: 1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
            departuresListCard(ride)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private let progressRingSegmentCount = 10
    private static let currentTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private func timeToDepartureCircle(_ ride: SavedRide) -> some View {
        let departures = departuresByRideId[ride.id] ?? []
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let dep = departures.first
            let isLoading = loadingRideIds.contains(ride.id)
            let hasNoDepartures = !isLoading && departures.isEmpty
            let isCancelled = dep.map { NextDepartureSummary.isCancelled($0) } ?? false
            let minutes = dep.flatMap { NextDepartureSummary.minutesTillArrival($0) }
            let timeText = dep.map { NextDepartureSummary.timeTillArrival($0) } ?? "—"
            let isNow = timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nu" || timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "now"
            let filledSegments: Int = (hasNoDepartures || isCancelled) ? 0 : (isNow ? progressRingSegmentCount : min(progressRingSegmentCount, max(0, minutes ?? 0)))
            let displayTime: String = hasNoDepartures
                ? "0 min"
                : (isCancelled
                    ? L10n.string("common.cancelled", language: currentLanguage)
                    : ((timeText == "—" || isNow) ? (isNow ? L10n.string("time.now", language: currentLanguage) : timeText) : timeText))
            let isUrgent = !hasNoDepartures && (isCancelled || isNow || (minutes ?? 99) <= 2)
            let ringColor: Color = hasNoDepartures ? Color.gray : (isUrgent ? Color(red: 230/255, green: 79/255, blue: 88/255) : Color(red: 20/255, green: 182/255, blue: 90/255))
            let departureTimeText: String = hasNoDepartures ? Self.currentTimeFormatter.string(from: context.date) : (dep.map { NextDepartureSummary.expectedTime($0) } ?? "—")
            let progress = CGFloat(filledSegments) / CGFloat(progressRingSegmentCount)
            let ringRadius: CGFloat = 110
            let busAngle = -90.0 + Double(progress) * 360.0
            let busRadians = busAngle * .pi / 180
            let busX = cos(busRadians) * ringRadius
            let busY = sin(busRadians) * ringRadius
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: CGFloat(filledSegments) / CGFloat(progressRingSegmentCount))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: filledSegments)
                    .opacity(hasNoDepartures ? 1.0 : circlePulseOpacity)

                if !hasNoDepartures, !isCancelled {
                    Image("bus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .offset(x: busX, y: busY)
                        .animation(.easeInOut(duration: 0.5), value: filledSegments)
                }

                VStack(spacing: 6) {
                    if isLoading && dep == nil {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(L10n.string("dashboard.loading", language: currentLanguage))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            LineDesignationBadge(designation: ride.lineDesignation)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text(displayTime)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(hasNoDepartures ? .secondary : (isUrgent ? Color(red: 230/255, green: 79/255, blue: 88/255) : .primary))
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text(departureTimeText)
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: 156)
                    }
                }
                .padding(24)
            }
            .frame(height: 260)
        }
    }

    @ViewBuilder
    private func carouselNavButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }

    @ViewBuilder
    private func departuresListCard(_ ride: SavedRide) -> some View {
        let departures = departuresByRideId[ride.id] ?? []
        let isLoading = loadingRideIds.contains(ride.id)
        let visibleCount = visibleDepartureCountByRideId[ride.id] ?? 0
        let listExiting = departuresListExitingByRideId[ride.id] ?? false

        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text(L10n.string("dashboard.nextDepartures", language: currentLanguage))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 8) {
                    Button {
                        mapRide = ride
                        showRideMap = true
                    } label: {
                        Image("map1")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .padding(.leading, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("dashboard.openMap", language: currentLanguage))

                    Spacer(minLength: 0)

                    Button { openSLApp() } label: {
                        Image("SL")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("dashboard.openSLApp", language: currentLanguage))
                }
            }
            .padding(.bottom, 9)

            if isLoading && departures.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.string("dashboard.loading", language: currentLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if departures.isEmpty {
                Text(L10n.string("dashboard.noDeparturesForLine", language: currentLanguage, ride.lineDesignation ?? "?"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(departures.prefix(5).enumerated()), id: \.element.id) { index, dep in
                        BusDepartureRow(departure: dep)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: UIColor { tc in
                                tc.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
                            }))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(index < visibleCount ? 1 : 0)
                            .scaleEffect(x: index < visibleCount ? 1 : 0.9, y: 1, anchor: .leading)
                            .offset(x: index < visibleCount ? 0 : -18)
                    }
                }
                .opacity(listExiting ? 0 : 1)
                .scaleEffect(x: listExiting ? 0.94 : 1, y: 1, anchor: .trailing)
                .offset(x: listExiting ? 22 : 0)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func syncSelectedRide() {
        guard !store.rides.isEmpty else {
            selectedRideId = nil
            return
        }
        if let current = selectedRideId, store.rides.contains(where: { $0.id == current }) { return }
        if let dashboard = store.dashboardRideId, store.rides.contains(where: { $0.id == dashboard }) {
            selectedRideId = dashboard
        } else {
            selectedRideId = store.rides.first?.id
        }
    }

    private var selectedRideIndex: Int? {
        guard let id = selectedRideId else { return nil }
        return store.rides.firstIndex(where: { $0.id == id })
    }

    private func canNavigateRide(by offset: Int) -> Bool {
        guard let index = selectedRideIndex else { return false }
        let target = index + offset
        return store.rides.indices.contains(target)
    }

    private func navigateRide(by offset: Int) {
        guard let index = selectedRideIndex else { return }
        let target = index + offset
        guard store.rides.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedRideId = store.rides[target].id
        }
    }

    private func startRefreshLoop() {
        refreshCancellable?.cancel()
        refreshCancellable = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !apiSleepManager.isSleeping else { return }
                for ride in store.rides {
                    Task { await refreshRide(ride, animateDepartures: true) }
                }
            }
    }

    private func startPulseLoop() {
        pulseCancellable?.cancel()
        pulseCancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !apiSleepManager.isSleeping else { return }
                guard !store.rides.isEmpty else { return }
                withAnimation(.easeInOut(duration: 1)) { circlePulseOpacity = 0.1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 1)) { circlePulseOpacity = 1.0 }
                }
            }
    }

    private func refreshRide(_ ride: SavedRide, animateDepartures: Bool) async {
        if await !ApiSleepManager.isApiAllowed() { return }
        let rideId = ride.id
        let previous = await MainActor.run {
            loadingRideIds.insert(rideId)
            return departuresByRideId[rideId] ?? []
        }
        let list = await fetchDeparturesForRide(ride)
        if animateDepartures && !previous.isEmpty {
            await MainActor.run {
                loadingRideIds.remove(rideId)
                withAnimation(.easeIn(duration: 0.1)) {
                    departuresListExitingByRideId[rideId] = true
                }
            }
            try? await Task.sleep(for: .milliseconds(105))
        } else {
            await MainActor.run {
                loadingRideIds.remove(rideId)
            }
        }
        await MainActor.run {
            departuresByRideId[rideId] = list
            departuresListExitingByRideId[rideId] = false
            if rideId == selectedRideId {
                store.setDashboardNextDeparture(list.first)
            }
            if animateDepartures {
                visibleDepartureCountByRideId[rideId] = 0
                animateDepartureReveal(for: rideId, count: list.count)
            } else {
                revealTasksByRideId[rideId]?.cancel()
                revealTasksByRideId[rideId] = nil
                visibleDepartureCountByRideId[rideId] = min(5, list.count)
            }
        }
    }

    private func animateDepartureReveal(for rideId: UUID, count: Int) {
        revealTasksByRideId[rideId]?.cancel()
        visibleDepartureCountByRideId[rideId] = 0
        let cappedCount = min(5, count)
        guard cappedCount > 0 else { return }
        let task = Task {
            for idx in 1...cappedCount {
                try? await Task.sleep(for: .milliseconds(24))
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        visibleDepartureCountByRideId[rideId] = idx
                    }
                }
            }
        }
        revealTasksByRideId[rideId] = task
    }

    private func fetchDeparturesForRide(_ ride: SavedRide) async -> [SLDeparture] {
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
                if !toDest.isEmpty { list = toDest }
            }
            return list
        } catch {
            return []
        }
    }

    private static let slAppURL = URL(string: "sl://")!
    private static let slAppStoreURL = URL(string: "https://apps.apple.com/app/id918418291")!

    private func openSLApp() {
        UIApplication.shared.open(Self.slAppURL) { opened in
            if !opened {
                UIApplication.shared.open(Self.slAppStoreURL)
            }
        }
    }
}

#Preview {
    DashboardCarouselView()
}
