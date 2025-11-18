import SwiftUI
import AppKit

struct AssignmentsMenuView: View {
    @ObservedObject var viewModel: AssignmentsViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject var updateInstaller: AppUpdateInstaller
    @Environment(\.openURL) private var openURL
    @State private var detailAssignment: Assignment?
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                settingsContent
            } else {
                assignmentsContent
            }
        }
        .frame(width: 430, height: 620)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showingSettings)
        .sheet(item: $detailAssignment) { assignment in
            AssignmentDetailView(assignment: assignment)
        }
    }

    private var assignmentsContent: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                header
                dateNavigator
                filterPicker
                if !viewModel.courseFilters.isEmpty {
                    courseFiltersView
                }
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
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            settingsToolbar
            Divider()
            SettingsView(settings: settings, updateChecker: updateChecker, updateInstaller: updateInstaller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var settingsToolbar: some View {
        ZStack {
            HStack {
                Button {
                    closeSettings()
                } label: {
                    Label("Assignments", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Done") {
                    closeSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Settings")
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    private var courseFiltersView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Courses", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isFilteringCourses {
                    Button("Clear") {
                        viewModel.clearCourseFilters()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.courseFilters) { filter in
                        Button {
                            viewModel.toggleCourseFilter(filter.name)
                        } label: {
                            HStack(spacing: 6) {
                                Text(filter.name)
                                    .lineLimit(1)
                                Text("\(filter.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(0.08))
                                    )
                            }
                        }
                        .buttonStyle(FilterChipStyle(isActive: viewModel.selectedCourses.contains(filter.name)))
                        .help("Show only \(filter.name)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
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
                            } : nil,
                            showDetails: assignment.hasDetails ? {
                                presentDetails(for: assignment)
                            } : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openAssignment(assignment)
                        }
                        .contextMenu {
                            if assignment.htmlURL != nil {
                                Button("Open in Canvas", systemImage: "safari") {
                                    openAssignment(assignment)
                                }
                            }
                            if assignment.hasDetails {
                                Button("View Details", systemImage: "text.justify.left") {
                                    presentDetails(for: assignment)
                                }
                            }
                            if let location = assignment.locationLine {
                                Button("Copy Location", systemImage: "doc.on.doc") {
                                    copyLocation(location)
                                }
                                if let mapsURL = assignment.mapsURL {
                                    Button("Open in Maps", systemImage: "map") {
                                        openURL(mapsURL)
                                    }
                                }
                            }
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

    private func presentDetails(for assignment: Assignment) {
        detailAssignment = assignment
    }

    private func copyLocation(_ location: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(location, forType: .string)
    }

    private func openSettings() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showingSettings = true
        }
    }

    private func closeSettings() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showingSettings = false
        }
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundColor(isActive ? Color.accentColor : Color.primary)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
