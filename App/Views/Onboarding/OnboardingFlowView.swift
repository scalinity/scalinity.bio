import SwiftUI
import UniformTypeIdentifiers

struct OnboardingFlowView: View {
    @EnvironmentObject private var app: AppViewModel
    @StateObject private var vm = OnboardingViewModel()

    @State private var isDropTargeted: Bool = false
    @State private var showImporter: Bool = false

    private let quotes = [
        "Small changes, compounding daily.",
        "Measure, adjust, repeat.",
        "Your future self is built today.",
        "Consistency beats intensity.",
    ]

    var body: some View {
        VStack(spacing: 16) {
            header
            progress
            content
            footer
        }
        .padding(24)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .commaSeparatedText]
        ) { result in
            if case let .success(url) = result {
                app.importProfile(from: url)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Onboarding")
                .font(.largeTitle.weight(.semibold))
            Text(quotes[vm.stepIndex % quotes.count])
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(vm.stepIndex + 1), total: 4)
            HStack {
                Text("Step \(vm.stepIndex + 1) of 4")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.stepIndex {
        case 0:
            importStep
        case 1:
            demographicsStep
        case 2:
            lifestyleStep
        default:
            reviewStep
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                vm.stepIndex = max(0, vm.stepIndex - 1)
            }
            .disabled(vm.stepIndex == 0)

            Spacer()

            Button(vm.stepIndex == 3 ? "Compute" : "Continue") {
                if vm.stepIndex == 3 {
                    app.currentProfile = vm.toProfile()
                    app.evaluateCurrentProfile()
                } else {
                    vm.stepIndex = min(3, vm.stepIndex + 1)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Steps

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upload your omics data")
                .font(.title2.weight(.semibold))

            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 2)
                )
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Drag & drop a CSV or JSON file")
                            .font(.headline)
                        Text("Or import a file / continue with manual entry.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                )
                .frame(height: 180)
                .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                    guard let item = providers.first else { return false }
                    _ = item.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async {
                            app.importProfile(from: url)
                        }
                    }
                    return true
                }

            HStack(spacing: 12) {
                Button("Import file…") { showImporter = true }
                Button("Use demo profile") { app.loadDemoProfile() }
                Spacer()
                Button("Manual entry") { vm.stepIndex = 1 }
            }

            if let profile = app.currentProfile {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loaded profile")
                        .font(.headline)
                    Text("\(Int(profile.chronologicalAge)) years • \(profile.sex.rawValue.capitalized) • \(profile.ethnicity)")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var demographicsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Basics")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Age")
                        .foregroundStyle(.secondary)
                    Stepper(value: $vm.draft.chronologicalAge, in: 0...120, step: 1) {
                        Text("\(Int(vm.draft.chronologicalAge))")
                    }
                }
                GridRow {
                    Text("Sex")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $vm.draft.sex) {
                        ForEach(Sex.allCases) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Ethnicity")
                        .foregroundStyle(.secondary)
                    TextField("Ethnicity", text: $vm.draft.ethnicity)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("BMI")
                        .foregroundStyle(.secondary)
                    TextField("BMI", value: $vm.draft.bmi, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Diabetes")
                        .foregroundStyle(.secondary)
                    Toggle("Comorbidity present", isOn: $vm.draft.comorbidityDiabetes)
                        .labelsHidden()
                }
            }
        }
    }

    private var lifestyleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lifestyle")
                .font(.title2.weight(.semibold))

            VStack(spacing: 14) {
                sliderRow(title: "Diet", value: $vm.draft.dietScore)
                sliderRow(title: "Exercise", value: $vm.draft.exerciseScore)
                sliderRow(title: "Sleep", value: $vm.draft.sleepScore)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key biomarkers (optional)")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                biomarkerField("Homocysteine (µmol/L)", value: $vm.draft.homocysteine)
                biomarkerField("Fasting glucose (mg/dL)", value: $vm.draft.fastingGlucose)
                biomarkerField("Fasting insulin (µIU/mL)", value: $vm.draft.fastingInsulin)
                biomarkerField("CRP (mg/L)", value: $vm.draft.crp)
                biomarkerField("IL-6 (pg/mL)", value: $vm.draft.il6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Review")
                    .font(.headline)
                Text("Missing values will be handled with KNN (k=5) against the bundled reference cohort.")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if app.isComputing {
                ProgressView("Computing biological age…")
            } else if let result = app.latestResult {
                Text(result.summary)
                    .font(.headline)
            } else if let err = app.lastError {
                Text(err)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - UI helpers

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: 1...10, step: 0.5)
            Text(String(format: "%.1f", value.wrappedValue))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func biomarkerField(_ title: String, value: Binding<Double?>) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
    }
}


