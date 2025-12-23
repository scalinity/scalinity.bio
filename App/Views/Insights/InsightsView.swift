import Charts
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Insights")
                    .font(.largeTitle.weight(.semibold))

                if let profile = app.currentProfile, let result = app.latestResult {
                    trajectoryCard(profile: profile, result: result)
                    driversCard(result: result)
                    regimenWheelCard()
                } else {
                    Text("Run a biological age calculation to unlock insights.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func trajectoryCard(profile: OmicsProfile, result: BiologicalAgeResult) -> some View {
        let delta = result.deltaYears
        let points = (0...10).map { i in
            (year: i, chrono: profile.chronologicalAge + Double(i), bio: profile.chronologicalAge + Double(i) + delta)
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("10-year trajectory (projection)")
                .font(.headline)
            Chart {
                ForEach(points, id: \.year) { p in
                    LineMark(
                        x: .value("Year", p.year),
                        y: .value("Chronological", p.chrono)
                    )
                    .foregroundStyle(.secondary)
                    .interpolationMethod(.catmullRom)
                }
                ForEach(points, id: \.year) { p in
                    LineMark(
                        x: .value("Year", p.year),
                        y: .value("Biological", p.bio)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 220)
            Text("Biological trajectory assumes the current age acceleration persists; use Regimen to explore what-if scenarios.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func driversCard(result: BiologicalAgeResult) -> some View {
        let top5 = Array(result.drivers.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Top aging drivers")
                .font(.headline)
            Chart {
                ForEach(top5) { d in
                    BarMark(
                        x: .value("Percent", d.percentContribution),
                        y: .value("Driver", d.title)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func regimenWheelCard() -> some View {
        let parts: [RadialBreakdownView.Slice] = [
            .init(label: "Nutrition", fraction: 0.40, color: Color.accentColor),
            .init(label: "Exercise", fraction: 0.30, color: Color.green),
            .init(label: "Sleep", fraction: 0.20, color: Color.purple),
            .init(label: "Supplements", fraction: 0.10, color: Color.orange),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Regimen breakdown (preview)")
                .font(.headline)

            HStack(spacing: 16) {
                RadialBreakdownView(slices: parts)
                    .frame(width: 160, height: 160)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parts, id: \.label) { s in
                        HStack {
                            Circle()
                                .fill(s.color)
                                .frame(width: 10, height: 10)
                            Text(s.label)
                            Spacer()
                            Text(String(format: "%.0f%%", s.fraction * 100))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("This becomes personalized once regimen generation (RAG + OpenRouter) is enabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


