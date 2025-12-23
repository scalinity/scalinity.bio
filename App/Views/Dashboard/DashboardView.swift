import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                mainCard
                if let result = app.latestResult {
                    driverCards(result: result)
                }
                if let err = app.lastError {
                    Text(err)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))
                Text("Biological age, drivers, and next actions.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.isComputing {
                ProgressView()
            }
        }
    }

    private var mainCard: some View {
        Group {
            if let profile = app.currentProfile, let result = app.latestResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        baScoreView(score: result.baScore)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Biological age")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f years", result.predictedBiologicalAge))
                                .font(.title.weight(.semibold))

                            Text(result.summary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            let rate = result.predictedBiologicalAge / max(1.0, profile.chronologicalAge)
                            Text(String(format: "You're aging %.2fx relative to chronological.", rate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("Last updated \(result.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Recompute") { app.evaluateCurrentProfile() }
                    }
                }
            } else if app.currentProfile != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to compute biological age.")
                        .font(.title2.weight(.semibold))
                    Text("We’ll normalize against the reference cohort, impute missing values with KNN(k=5), and run on-device CoreML inference.")
                        .foregroundStyle(.secondary)
                    Button("Compute biological age") { app.evaluateCurrentProfile() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No profile loaded")
                        .font(.title2.weight(.semibold))
                    Text("Import a CSV/JSON omics profile or start onboarding.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Use demo profile") { app.loadDemoProfile() }
                        Button("Go to Onboarding") {
                            // Sidebar contains Profile → Onboarding. Keep this lightweight.
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func driverCards(result: BiologicalAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top drivers")
                .font(.headline)
            ForEach(result.drivers) { d in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%.0f%%", d.percentContribution))
                        .font(.headline.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title)
                            .font(.headline)
                        Text(d.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func baScoreView(score: Double) -> some View {
        let color: Color = {
            if score < 45 { return Color(red: 0.20, green: 0.78, blue: 0.35) } // green-ish
            if score > 55 { return Color(red: 1.0, green: 0.23, blue: 0.19) } // red-ish
            return Color(red: 0.0, green: 0.48, blue: 1.0) // blue-ish
        }()

        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 2)
            VStack(spacing: 4) {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("BA score")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, height: 140)
    }
}


