//
//  TermsPrivacyView.swift
//  Rödbuss
//

import SwiftUI

struct TermsPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    Text(L10n.string("termsPrivacy.tabTerms", language: currentLanguage)).tag(0)
                    Text(L10n.string("termsPrivacy.tabPrivacy", language: currentLanguage)).tag(1)
                    Text(L10n.string("termsPrivacy.tabDisclaimer", language: currentLanguage)).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(contentText)
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.string("termsPrivacy.title", language: currentLanguage))
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

    private var contentText: String {
        switch selectedTab {
        case 0:
            return L10n.string("termsPrivacy.termsContent", language: currentLanguage)
        case 1:
            return L10n.string("termsPrivacy.privacyContent", language: currentLanguage)
        default:
            return L10n.string("termsPrivacy.disclaimerContent", language: currentLanguage)
        }
    }
}

#Preview {
    TermsPrivacyView()
}
