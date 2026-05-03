//
//  SettingsView.swift
//  Rödbuss
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "Swedish"
    @AppStorage("trafiklabApiKey") private var trafiklabApiKey: String = ""
    @State private var showLanguageSelection: Bool = false
    @State private var showTermsPrivacy: Bool = false
    @State private var showHelpSupport: Bool = false
    @State private var showAbout: Bool = false
    @State private var showClearHistoryAlert: Bool = false
    @State private var showTrafiklabApiKeySheet: Bool = false
    @State private var showSleepTimePicker: Bool = false

    private let lastSearchKey = "lastSearchState"

    private var settingsCardBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
        })
    }

    private func settingRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        trailing: @escaping () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(iconColor.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.system(size: 16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func settingButton(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingRow(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // PREFERENCES
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L10n.string("settings.preferences", language: currentLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                // Dark mode
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "moon.fill")
                                                .foregroundColor(.purple)
                                                .font(.system(size: 16))
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.string("settings.darkMode", language: currentLanguage))
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(L10n.string("settings.darkModeSubtitle", language: currentLanguage))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $isDarkMode)
                                        .labelsHidden()
                                        .scaleEffect(0.75)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                Divider()
                                    .background(Color(.separator))
                                    .padding(.leading, 60)

                                // Language
                                Button(action: { showLanguageSelection = true }) {
                                    settingRow(icon: "globe", iconColor: .blue, title: L10n.string("settings.language", language: currentLanguage), subtitle: L10n.string("settings.languageSubtitle", language: currentLanguage)) {
                                        HStack(spacing: 4) {
                                            Text(selectedLanguage == "English" ? L10n.string("language.english", language: currentLanguage) : L10n.string("language.swedish", language: currentLanguage))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .background(Color(.separator))
                                    .padding(.leading, 60)

                                // Clear history
                                settingButton(
                                    icon: "trash.fill",
                                    iconColor: .red,
                                    title: L10n.string("settings.clearHistory", language: currentLanguage),
                                    subtitle: L10n.string("settings.clearHistorySubtitle", language: currentLanguage)
                                ) {
                                    showClearHistoryAlert = true
                                }

                            }
                            .background(settingsCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // SUPPORT
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L10n.string("settings.support", language: currentLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                settingButton(
                                    icon: "questionmark.circle.fill",
                                    iconColor: .blue,
                                    title: L10n.string("settings.helpSupport", language: currentLanguage),
                                    subtitle: L10n.string("settings.helpSupportSubtitle", language: currentLanguage)
                                ) {
                                    showHelpSupport = true
                                }

                                Divider()
                                    .background(Color(.separator))
                                    .padding(.leading, 60)

                                settingButton(
                                    icon: "lock.fill",
                                    iconColor: .green,
                                    title: L10n.string("settings.termsPrivacy", language: currentLanguage),
                                    subtitle: L10n.string("settings.termsPrivacySubtitle", language: currentLanguage)
                                ) {
                                    showTermsPrivacy = true
                                }

                                Divider()
                                    .background(Color(.separator))
                                    .padding(.leading, 60)

                                settingButton(
                                    icon: "info.circle.fill",
                                    iconColor: .orange,
                                    title: L10n.string("settings.about", language: currentLanguage),
                                    subtitle: L10n.string("settings.aboutSubtitle", language: currentLanguage)
                                ) {
                                    showAbout = true
                                }
                            }
                            .background(settingsCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // API INFO
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L10n.string("settings.apiInfo", language: currentLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                Button(action: { showSleepTimePicker = true }) {
                                    settingRow(
                                        icon: "moon.zzz.fill",
                                        iconColor: .indigo,
                                        title: L10n.string("settings.sleepTime", language: currentLanguage),
                                        subtitle: L10n.string("settings.sleepTimeSubtitle", language: currentLanguage)
                                    ) {
                                        HStack(spacing: 4) {
                                            Text("\(apiSleepManager.sleepAfterMinutes) min")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .background(Color(.separator))
                                    .padding(.leading, 60)

                                settingButton(
                                    icon: "map.fill",
                                    iconColor: .orange,
                                    title: L10n.string("settings.trafiklabKey", language: currentLanguage),
                                    subtitle: L10n.string("settings.trafiklabKeySubtitle", language: currentLanguage)
                                ) {
                                    showTrafiklabApiKeySheet = true
                                }
                                .disabled(true)
                                .opacity(0.45)
                            }
                            .background(settingsCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(L10n.string("settings.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLanguageSelection) {
                LanguageSelectionView(selectedLanguage: $selectedLanguage)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTermsPrivacy) {
                TermsPrivacyView()
            }
            .sheet(isPresented: $showHelpSupport) {
                HelpSupportView()
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showTrafiklabApiKeySheet) {
                TrafiklabApiKeyView(apiKey: $trafiklabApiKey)
            }
            .sheet(isPresented: $showSleepTimePicker) {
                SleepTimeSelectionView()
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .alert(L10n.string("settings.clearHistoryAlertTitle", language: currentLanguage), isPresented: $showClearHistoryAlert) {
                Button(L10n.string("settings.clear", language: currentLanguage), role: .destructive) {
                    clearHistory()
                }
                Button(L10n.string("settings.cancel", language: currentLanguage), role: .cancel) { }
            } message: {
                Text(L10n.string("settings.clearHistoryAlertMessage", language: currentLanguage))
            }
        }
    }

    private func clearHistory() {
        UserDefaults.standard.removeObject(forKey: lastSearchKey)
        SitesCache.shared.clearCache()
    }
}

private struct SleepTimeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @ObservedObject private var apiSleepManager = ApiSleepManager.shared
    @State private var selectedMinutes: Int = ApiSleepManager.shared.sleepAfterMinutes

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L10n.string("settings.sleepTime", language: currentLanguage), selection: $selectedMinutes) {
                    ForEach(1...60, id: \.self) { minute in
                        Text("\(minute) min")
                            .tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L10n.string("settings.sleepTime", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) {
                        apiSleepManager.updateSleepAfterMinutes(selectedMinutes)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Language selection

private struct LanguageSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @Binding var selectedLanguage: String

    private let languages = ["English", "Swedish"]
    
    private func flag(for language: String) -> String {
        switch language {
        case "English": return "🇺🇸"
        case "Swedish": return "🇸🇪"
        default: return "🌐"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(languages, id: \.self) { language in
                    HStack {
                        Text(flag(for: language))
                            .font(.body)
                        Text(language == "English" ? L10n.string("language.english", language: currentLanguage) : L10n.string("language.swedish", language: currentLanguage))
                            .foregroundStyle(.primary)
                        Spacer()
                        if language == selectedLanguage {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(red: 20/255, green: 182/255, blue: 90/255))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLanguage = language
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L10n.string("language.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Trafiklab API key modal

private struct TrafiklabApiKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @Binding var apiKey: String
    @State private var isKeyVisible: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if isKeyVisible {
                            TextField(L10n.string("settings.trafiklabKey", language: currentLanguage), text: $apiKey)
                                .font(.system(size: 13))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                        } else {
                            SecureField(L10n.string("settings.trafiklabKey", language: currentLanguage), text: $apiKey)
                                .font(.system(size: 13))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                        }
                        Button(action: { isKeyVisible.toggle() }) {
                            Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundStyle(.secondary)
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L10n.string("settings.trafiklabKeySubtitle", language: currentLanguage))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L10n.string("settings.trafiklabKey", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.ok", language: currentLanguage)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Placeholder support views

private struct TermsPrivacyPlaceholderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(L10n.string("termsPrivacy.placeholder", language: currentLanguage))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.string("termsPrivacy.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) { dismiss() }
                }
            }
        }
    }
}

private struct HelpSupportPlaceholderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(L10n.string("helpSupport.placeholder", language: currentLanguage))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.string("helpSupport.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) { dismiss() }
                }
            }
        }
    }
}

private struct AboutPlaceholderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(L10n.string("about.appName", language: currentLanguage))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(L10n.string("about.tagline", language: currentLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.string("about.title", language: currentLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
