import SwiftUI
import AppKit

struct AssignmentsMenuView: View {
    @ObservedObject var viewModel: AssignmentsViewModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header
                dateNavigator
                filterPicker
                if settings.showAssignmentTracker && viewModel.hasTrackableAssignments {
                    progressSummary
                }
                Divider()
                content
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
                Divider()
                footer
            }
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .overlay(alignment: .topTrailing) {
                if viewModel.hasOffset {
                    Button("Today") {
                        viewModel.goToToday()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
            }
        }
        .frame(width: 430, height: 620)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Canvas")
                    .font(.headline)
                if let last = viewModel.lastUpdatedAt {
                    Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settings.isConfigured() {
                    Text("Sync ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add your Canvas info in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var dateNavigator: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            VStack(spacing: 1) {
                Text(viewModel.dateTitle)
                    .font(.title3.weight(.semibold))
                Text(viewModel.dateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .controlSize(.small)
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $viewModel.filter) {
            ForEach(AssignmentsViewModel.AssignmentFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's assignments")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(viewModel.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.progressValue)
                .animation(.easeInOut, value: viewModel.progressValue)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var content: some View {
        if !settings.isConfigured() {
            EmptyStateView(
                systemImage: "key.fill",
                title: "Connect Canvas",
                message: settings.dataSource == .apiToken ? "Add your Canvas domain and API token." : "Paste your Canvas calendar feed URL.",
                actionTitle: "Open Settings"
            ) {
                openSettings()
            }
        } else if viewModel.isLoading && viewModel.assignments.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(viewModel.dateTitle.lowercased()) schedule…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .frame(maxHeight: .infinity, alignment: .center)
        } else if viewModel.assignments.isEmpty {
            EmptyStateView(
                systemImage: "sun.max.fill",
                title: "No due dates today",
                message: "Enjoy your day!"
            )
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.assignments) { assignment in
                        AssignmentRowView(
                            assignment: assignment,
                            isCompleted: viewModel.isCompleted(assignment),
                            showsTracker: settings.showAssignmentTracker,
                            toggleCompletion: (settings.showAssignmentTracker && assignment.kind == .assignment) ? {
                                viewModel.toggleCompletion(for: assignment)
                            } : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openAssignment(assignment)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                viewModel.manualRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }

    private func openAssignment(_ assignment: Assignment) {
        guard let url = assignment.htmlURL else { return }
        openURL(url)
    }

    private func openSettings() {
        SettingsWindowPresenter.shared.present(settings: settings)
    }
}
