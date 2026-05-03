//
//  ContentView.swift
//  Rödbuss
//
//  Created by EVYATAR DAYAN on 2026-02-17.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "Swedish"
    @State private var selectedTab: Int = 2 // Default to Favorite (center tab)
    @ObservedObject private var injectedStore = InjectedSearchStore.shared
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared

    private let menuHeight: CGFloat = 40
    private let menuButtonSpacing: CGFloat = -40

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case 0:
                            DashboardCarouselView()
                        case 1:
                            MyRidesView()
                        case 2:
                            FavoriteView()
                        case 3:
                            SearchView()
                        case 4:
                            SettingsView()
                        default:
                            SearchView()
                        }
                    }
                    .environment(\.currentLanguage, selectedLanguage)
                    .frame(width: geometry.size.width, height: geometry.size.height - menuHeight)
                    .clipped()
                    .onChange(of: injectedStore.requestSwitchToSearchAndRun) { _, new in
                        if new {
                            selectedTab = 3
                            injectedStore.clearRequestSwitchToSearchAndRun()
                        }
                    }
                    .onChange(of: injectedStore.requestSwitchToMyRides) { _, new in
                        if new {
                            selectedTab = 1
                            injectedStore.clearRequestSwitchToMyRides()
                        }
                    }

                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20)
                                .fill(Color(.systemBackground))
                                .frame(width: geometry.size.width, height: menuHeight)
                                .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: -3)

                            Rectangle()
                                .fill(Color(.systemBackground))
                                .frame(width: geometry.size.width)
                                .frame(height: geometry.safeAreaInsets.bottom)
                        }

                        HStack(spacing: menuButtonSpacing) {
                            TabBarButton(
                                icon: "square.grid.2x2.fill",
                                label: L10n.string("tab.map", language: selectedLanguage),
                                isSelected: selectedTab == 0,
                                action: { selectedTab = 0 }
                            )

                            TabBarButton(
                                icon: "bus.fill",
                                label: L10n.string("tab.myRides", language: selectedLanguage),
                                isSelected: selectedTab == 1,
                                action: { selectedTab = 1 }
                            )

                            TabBarButton(
                                icon: "star.fill",
                                label: L10n.string("tab.dashboard", language: selectedLanguage),
                                isSelected: selectedTab == 2,
                                action: { selectedTab = 2 }
                            )

                            TabBarButton(
                                icon: "magnifyingglass",
                                label: L10n.string("tab.search", language: selectedLanguage),
                                isSelected: selectedTab == 3,
                                action: { selectedTab = 3 }
                            )

                            TabBarButton(
                                icon: "gearshape.fill",
                                label: L10n.string("tab.settings", language: selectedLanguage),
                                isSelected: selectedTab == 4,
                                action: { selectedTab = 4 }
                            )
                        }
                        .frame(width: geometry.size.width, height: menuHeight)
                    }
                    .zIndex(1)
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            apiSleepManager.startCycle()
        }
        .alert(
            L10n.string("sleepPopup.title", language: selectedLanguage),
            isPresented: Binding(
                get: { apiSleepManager.isSleeping },
                set: { _ in }
            )
        ) {
            Button(L10n.string("sleepPopup.wakeUp", language: selectedLanguage)) {
                apiSleepManager.wakeUp()
            }
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, -30)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
    }
}

struct PlaceholderTabView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
