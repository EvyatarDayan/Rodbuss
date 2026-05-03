//
//  FavoriteView.swift
//  Rödbuss
//
//  Shows one route selected from My Rides as the favorite view. Default center tab.
//

import Combine
import SwiftUI

struct FavoriteView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var store = MyRidesStore.shared
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared
    @State private var isLoading = false
    @State private var lineDepartures: [SLDeparture] = []
    @State private var refreshCancellable: AnyCancellable?
    @State private var pulseCancellable: AnyCancellable?
    @State private var circlePulseOpacity: Double = 1.0
    @State private var showRideMap = false
    @State private var visibleDepartureCount = 0
    @State private var departuresListExiting = false
    @State private var revealTask: Task<Void, Never>?

    private var dashboardRide: SavedRide? {
        guard let id = store.dashboardRideId else { return nil }
        return store.rides.first { $0.id == id }
    }

    private var dashboardCardBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
        })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let ride = dashboardRide {
                    dashboardContent(ride: ride)
                } else {
                    emptyState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: store.dashboardRideId) {
                if dashboardRide != nil {
                    await refreshNextDeparture(animateDepartures: false)
                }
            }
            .onChange(of: store.dashboardRideId) { _, newId in
                if newId != nil {
                    Task { await refreshNextDeparture(animateDepartures: false) }
                }
            }
            .onAppear {
                refreshCancellable = Timer.publish(every: 10, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        guard !apiSleepManager.isSleeping else { return }
                        if dashboardRide != nil {
                            Task { await refreshNextDeparture(animateDepartures: true) }
                        }
                    }
                pulseCancellable = Timer.publish(every: 3, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        guard !apiSleepManager.isSleeping else { return }
                        guard dashboardRide != nil else { return }
                        withAnimation(.easeInOut(duration: 1)) { circlePulseOpacity = 0.1 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 1)) { circlePulseOpacity = 1.0 }
                        }
                    }
            }
            .onDisappear {
                refreshCancellable?.cancel()
                refreshCancellable = nil
                pulseCancellable?.cancel()
                pulseCancellable = nil
                revealTask?.cancel()
                revealTask = nil
            }
            .sheet(isPresented: $showRideMap) {
                if let ride = dashboardRide {
                    RideMapModalView(ride: ride, upcomingDeparture: store.dashboardNextDeparture)
                }
            }
            .onChange(of: apiSleepManager.isSleeping) { _, isSleeping in
                if !isSleeping, dashboardRide != nil {
                    Task { await refreshNextDeparture(animateDepartures: true) }
                }
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(.all)
            ContentUnavailableView(
                L10n.string("dashboard.emptyTitle", language: currentLanguage),
                systemImage: "house",
                description: Text(L10n.string("dashboard.emptySubtitle", language: currentLanguage))
            )
        }
    }

    private let progressRingSegmentCount = 10

    @ViewBuilder
    private func dashboardContent(ride: SavedRide) -> some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(.all)

            VStack(alignment: .center, spacing: 28) {
                SavedRideRouteTitleRow(ride: ride, centerRouteLine: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

                timeToDepartureCircle(ride: ride)

                nextDeparturesList(ride: ride)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private static let currentTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private func timeToDepartureCircle(ride: SavedRide) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let hasNoDepartures = !isLoading && lineDepartures.isEmpty
            let dep = store.dashboardNextDeparture
            let isCancelled = dep.map { NextDepartureSummary.isCancelled($0) } ?? false
            let minutes = dep.flatMap { NextDepartureSummary.minutesTillArrival($0) }
            let timeText = dep.map { NextDepartureSummary.timeTillArrival($0) } ?? "—"
            let isNu = timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nu" || timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "now"
            let filledSegments: Int = (hasNoDepartures || isCancelled) ? 0 : (isNu ? progressRingSegmentCount : min(progressRingSegmentCount, max(0, minutes ?? 0)))
            let displayTime: String = hasNoDepartures
                ? "0 min"
                : (isCancelled
                    ? L10n.string("common.cancelled", language: currentLanguage)
                    : ((timeText == "—" || isNu) ? (isNu ? L10n.string("time.now", language: currentLanguage) : timeText) : timeText))
            let isUrgent = !hasNoDepartures && (isCancelled || isNu || (minutes ?? 99) <= 2)
            let ringColor: Color = hasNoDepartures ? Color.gray : (isUrgent ? Color.appRed : Color.appGreen)
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
                                .foregroundStyle(hasNoDepartures ? .secondary : (isUrgent ? Color.appRed : .primary))
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

    private static let slAppURL = URL(string: "sl://")!
    private static let slAppStoreURL = URL(string: "https://apps.apple.com/app/id918418291")!

    private func openSLApp() {
        UIApplication.shared.open(Self.slAppURL) { opened in
            if !opened {
                UIApplication.shared.open(Self.slAppStoreURL)
            }
        }
    }

    @ViewBuilder
    private func nextDeparturesList(ride: SavedRide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text(L10n.string("dashboard.nextDepartures", language: currentLanguage))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 8) {
                    Button {
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

                    Button { openSLApp()
                    } label: {
                        Image("SL")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("dashboard.openSLApp", language: currentLanguage))
                }
            }
//            .frame(maxWidth: .infinity)
            .padding(.bottom, 9)

            if isLoading && lineDepartures.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.string("dashboard.loading", language: currentLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if lineDepartures.isEmpty {
                Text(L10n.string("dashboard.noDeparturesForLine", language: currentLanguage, ride.lineDesignation ?? "?"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(lineDepartures.prefix(5).enumerated()), id: \.element.id) { index, dep in
                        BusDepartureRow(departure: dep)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(dashboardCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .opacity(index < visibleDepartureCount ? 1 : 0)
                            .scaleEffect(x: index < visibleDepartureCount ? 1 : 0.9, y: 1, anchor: .leading)
                            .offset(x: index < visibleDepartureCount ? 0 : -18)
                    }
                }
                .opacity(departuresListExiting ? 0 : 1)
                .scaleEffect(x: departuresListExiting ? 0.94 : 1, y: 1, anchor: .trailing)
                .offset(x: departuresListExiting ? 22 : 0)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func refreshNextDeparture(animateDepartures: Bool) async {
        if await !ApiSleepManager.isApiAllowed() { return }
        guard let ride = dashboardRide else { return }
        let rideId = ride.id
        let hadContent = await MainActor.run {
            isLoading = true
            return !lineDepartures.isEmpty
        }
        let list = await fetchDeparturesForRide(ride)
        if animateDepartures && hadContent {
            await MainActor.run {
                guard dashboardRide?.id == rideId else {
                    isLoading = false
                    departuresListExiting = false
                    return
                }
                withAnimation(.easeIn(duration: 0.1)) {
                    departuresListExiting = true
                }
            }
            try? await Task.sleep(for: .milliseconds(105))
        }
        await MainActor.run {
            guard dashboardRide?.id == rideId else {
                isLoading = false
                departuresListExiting = false
                return
            }
            lineDepartures = list
            departuresListExiting = false
            store.setDashboardNextDeparture(list.first)
            isLoading = false
            if animateDepartures {
                visibleDepartureCount = 0
                animateDepartureReveal(count: list.count)
            } else {
                revealTask?.cancel()
                revealTask = nil
                visibleDepartureCount = min(5, list.count)
            }
        }
    }

    private func animateDepartureReveal(count: Int) {
        revealTask?.cancel()
        visibleDepartureCount = 0
        let cappedCount = min(5, count)
        guard cappedCount > 0 else { return }
        revealTask = Task {
            for idx in 1...cappedCount {
                try? await Task.sleep(for: .milliseconds(24))
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        visibleDepartureCount = idx
                    }
                }
            }
        }
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
}

private extension Color {
    static let appGreen = Color(red: 20/255, green: 182/255, blue: 90/255)
    static let appRed = Color(red: 230/255, green: 79/255, blue: 88/255)
}

#Preview {
    FavoriteView()
}
