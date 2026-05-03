//
//  AboutView.swift
//  Rödbuss
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(L10n.string("about.versionPrefix", language: currentLanguage)) \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .center, spacing: 8) {
                        Text(appVersion)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.string("about.sectionAppTitle", language: currentLanguage))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(L10n.string("about.sectionAppBody1", language: currentLanguage))
                            .font(.body)
                            .multilineTextAlignment(.leading)

                        Text(L10n.string("about.sectionAppBody2", language: currentLanguage))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.string("about.sectionCompanyTitle", language: currentLanguage))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(L10n.string("about.sectionCompanyBody1", language: currentLanguage))
                            .font(.body)
                            .multilineTextAlignment(.leading)

                        Text(L10n.string("about.sectionCompanyBody2", language: currentLanguage))
                            .font(.body)
                            .multilineTextAlignment(.leading)

                        Text(L10n.string("about.sectionCompanyBody3", language: currentLanguage))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.string("about.title", language: currentLanguage))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.done", language: currentLanguage)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AboutView()
}
