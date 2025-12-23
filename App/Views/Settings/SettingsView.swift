import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppViewModel

    @AppStorage("scalinity_consent_analytics") private var consentAnalytics: Bool = false

    @State private var openRouterKey: String = ""
    @State private var entrezKey: String = ""
    @State private var dbKey: String = ""
    @State private var savedMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))

                apiKeysCard
                privacyCard

                if let msg = savedMessage {
                    Text(msg)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .onAppear {
                openRouterKey = app.environmentConfig.secret(.openRouterApiKey) ?? ""
                entrezKey = app.environmentConfig.secret(.entrezApiKey) ?? ""
                dbKey = app.environmentConfig.secret(.databaseEncryptionKey) ?? ""
            }
        }
    }

    private var apiKeysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Keys")
                .font(.headline)
            Text("Keys can be provided via environment variables or saved locally in Keychain from here.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("OpenRouter")
                        .foregroundStyle(.secondary)
                    SecureField("OPENROUTER_API_KEY", text: $openRouterKey)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Entrez (NCBI)")
                        .foregroundStyle(.secondary)
                    SecureField("ENTREZ_API_KEY", text: $entrezKey)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("DB encryption")
                        .foregroundStyle(.secondary)
                    SecureField("DATABASE_ENCRYPTION_KEY", text: $dbKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Save to Keychain") {
                    do {
                        if !openRouterKey.isEmpty { try app.environmentConfig.setSecret(openRouterKey, for: .openRouterApiKey) }
                        if !entrezKey.isEmpty { try app.environmentConfig.setSecret(entrezKey, for: .entrezApiKey) }
                        if !dbKey.isEmpty { try app.environmentConfig.setSecret(dbKey, for: .databaseEncryptionKey) }
                        savedMessage = "Saved."
                    } catch {
                        savedMessage = "Save failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy & consent")
                .font(.headline)
            Toggle("Allow anonymized interaction data for weekly retraining (explicit consent)", isOn: $consentAnalytics)

            Text("If enabled, the app will store only encrypted, anonymized interaction signals locally. Export for retraining is opt-in and manual by default.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


