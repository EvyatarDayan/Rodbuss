//
//  HelpSupportView.swift
//  Rödbuss
//

import SwiftUI

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentLanguage) private var currentLanguage

    @State private var fullName = ""
    @State private var email = ""
    @State private var subject = ""
    @State private var description = ""
    @State private var showForm = false
    @State private var showError = false
    @State private var alertType: AlertType = .none

    enum AlertType {
        case none
        case messageSent
    }

    private let supportEmail = "abashelariprod@gmail.com"
    private let supportWebsite = "https://www.abashelari.com"

    private var allFieldsFilled: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if showForm {
                    contactForm
                } else {
                    supportLanding
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(showForm
                         ? L10n.string("helpSupport.contactSupportTitle", language: currentLanguage)
                         : L10n.string("helpSupport.title", language: currentLanguage))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if showForm {
                        Button(L10n.string("settings.cancel", language: currentLanguage)) {
                            showForm = false
                        }
                    } else {
                        Button(L10n.string("helpSupport.close", language: currentLanguage)) {
                            dismiss()
                        }
                    }
                }
            }
            .alert(isPresented: Binding(
                get: { alertType != .none },
                set: { if !$0 { alertType = .none } }
            )) {
                switch alertType {
                case .messageSent:
                    return Alert(
                        title: Text(L10n.string("helpSupport.messageSentTitle", language: currentLanguage)),
                        message: Text(L10n.string("helpSupport.messageSentBody", language: currentLanguage)),
                        dismissButton: .default(Text(L10n.string("common.ok", language: currentLanguage))) {
                            dismiss()
                        }
                    )
                case .none:
                    return Alert(title: Text(""), message: Text(""), dismissButton: .default(Text("")))
                }
            }
        }
    }

    private var supportLanding: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .center, spacing: 30) {
                VStack(alignment: .center, spacing: 14) {
                    Text(L10n.string("helpSupport.landingTitle", language: currentLanguage))
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(L10n.string("helpSupport.landingLine1", language: currentLanguage))
                        .font(.body)
                    Text(L10n.string("helpSupport.landingLine2", language: currentLanguage))
                        .font(.body)
                    Text(L10n.string("helpSupport.landingLine3", language: currentLanguage))
                        .font(.body)

                    Divider()
                        .padding(.vertical, 8)
                        .padding(.top, 24)

                    Text("\(L10n.string("helpSupport.emailLabel", language: currentLanguage)): \(supportEmail)")
                        .font(.subheadline)
                    Text("\(L10n.string("helpSupport.websiteLabel", language: currentLanguage)): \(supportWebsite)")
                        .font(.subheadline)

                    Divider()
                        .padding(.vertical, 8)
                        .padding(.top, 20)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)

                Button {
                        showForm = true
                    } label: {
                        Text(L10n.string("helpSupport.contactFormButton", language: currentLanguage))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(red: 20/255, green: 182/255, blue: 90/255))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                .padding(.horizontal, 28)

                Text(L10n.string("helpSupport.replyTime", language: currentLanguage))
                    .font(.body)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 28)
    }

    private var contactForm: some View {
        Form {
            Section(header: Text(L10n.string("helpSupport.fullNameHeader", language: currentLanguage))) {
                TextField(L10n.string("helpSupport.fullNamePlaceholder", language: currentLanguage), text: $fullName)
            }

            Section(header: Text(L10n.string("helpSupport.emailHeader", language: currentLanguage))) {
                TextField(L10n.string("helpSupport.emailPlaceholder", language: currentLanguage), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section(header: Text(L10n.string("helpSupport.subjectHeader", language: currentLanguage))) {
                TextField(L10n.string("helpSupport.subjectPlaceholder", language: currentLanguage), text: $subject)
                    .onChange(of: subject) { _, newValue in
                        if newValue.count > 100 {
                            subject = String(newValue.prefix(100))
                        }
                    }
                HStack {
                    Spacer()
                    Text("\(subject.count)/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(L10n.string("helpSupport.descriptionHeader", language: currentLanguage))) {
                TextEditor(text: $description)
                    .frame(height: 120)
                    .onChange(of: description) { _, newValue in
                        if newValue.count > 400 {
                            description = String(newValue.prefix(400))
                        }
                    }
                HStack {
                    Spacer()
                    Text("\(description.count)/400")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showError && !allFieldsFilled {
                Section {
                    Text(L10n.string("helpSupport.allFieldsRequired", language: currentLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    if allFieldsFilled {
                        showError = false
                        alertType = .messageSent
                    } else {
                        showError = true
                    }
                } label: {
                    Text(L10n.string("helpSupport.send", language: currentLanguage))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(allFieldsFilled ? Color(red: 20/255, green: 182/255, blue: 90/255) : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!allFieldsFilled)
            }
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    HelpSupportView()
}
