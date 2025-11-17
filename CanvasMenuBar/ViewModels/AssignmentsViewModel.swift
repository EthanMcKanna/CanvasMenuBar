import Foundation
import Combine

@MainActor
final class AssignmentsViewModel: ObservableObject {
    enum AssignmentFilter: String, CaseIterable, Identifiable {
        case all
        case assignments
        case events

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .assignments: return "Assignments"
            case .events: return "Events"
            }
        }
    }

    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedDate: Date
    @Published private(set) var completedIDs: Set<String> = []
    @Published var filter: AssignmentFilter {
        didSet {
            defaults.set(filter.rawValue, forKey: filterDefaultsKey)
            applyFilter()
        }
    }

    private let settings: SettingsStore
    private let api: CanvasAPI
    private let completionStore: CompletionStore
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var allAssignments: [Assignment] = []
    private var todayAssignments: [Assignment] = []
    private var assignmentCache: [String: [Assignment]] = [:]
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
    private var fetchGeneration = 0
    private let defaults: UserDefaults
    private let filterDefaultsKey = "AssignmentsFilter"

    init(settings: SettingsStore,
         api: CanvasAPI = CanvasAPI(),
         completionStore: CompletionStore = CompletionStore(),
         defaults: UserDefaults = .standard) {
        self.settings = settings
        self.api = api
        self.completionStore = completionStore
        self.defaults = defaults
        let storedFilterRaw = defaults.string(forKey: filterDefaultsKey)
        self.filter = AssignmentFilter(rawValue: storedFilterRaw ?? "") ?? .all
        self.selectedDate = Calendar.current.startOfDay(for: Date())
        self.completedIDs = completionStore.completions(for: self.selectedDate)
        observeSettings()
        restartTimer()
        Task { await refresh(reason: .initialLoad) }
    }

    enum RefreshReason {
        case initialLoad
        case manual
        case timer
        case configuration
    }

    func refresh(reason: RefreshReason = .manual) async {
        guard let configuration = settings.sourceConfiguration() else {
            assignments = []
            allAssignments = []
            errorMessage = settings.dataSource == .apiToken ? "Add your Canvas URL and token in Settings." : "Paste your Canvas calendar feed URL in Settings."
            lastUpdatedAt = nil
            return
        }

        fetchGeneration += 1
        let generation = fetchGeneration
        let targetDate = selectedDate
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await fetchAssignments(for: targetDate, configuration: configuration)
            processFetched(fetched, for: targetDate)
            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                lastUpdatedAt = Date()
            }
            prefetchAdjacentDays(from: targetDate, configuration: configuration)
        } catch {
            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                errorMessage = error.localizedDescription
            }
        }

        if generation == fetchGeneration {
            isLoading = false
        }
    }

    func manualRefresh() {
        Task { await refresh(reason: .manual) }
    }

    func changeDay(by delta: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        prepareForNewDate(Calendar.current.startOfDay(for: newDate))
        Task { await refresh(reason: .configuration) }
    }

    func goToToday() {
        prepareForNewDate(Calendar.current.startOfDay(for: Date()))
        Task { await refresh(reason: .configuration) }
    }

    func isCompleted(_ assignment: Assignment) -> Bool {
        completedIDs.contains(assignment.id)
    }

    func toggleCompletion(for assignment: Assignment) {
        completedIDs = completionStore.toggle(id: assignment.id, on: selectedDate)
    }

    var hasOffset: Bool {
        !Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    var dateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(selectedDate) {
            return "Tomorrow"
        }
        if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday"
        }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }

    var dateSubtitle: String {
        selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    var progressText: String {
        let total = trackableAssignmentsCount
        guard total > 0 else { return "No assignments tracked" }
        let completed = completedAssignmentsCount
        return "Completed \(completed)/\(total)"
    }

    var progressValue: Double {
        let total = trackableAssignmentsCount
        guard total > 0 else { return 0 }
        return Double(completedAssignmentsCount) / Double(total)
    }

    var hasTrackableAssignments: Bool {
        trackableAssignmentsCount > 0
    }

    var remainingAssignmentsCount: Int {
        let targetAssignments = badgeAssignments()
        guard !targetAssignments.isEmpty else { return 0 }
        let badgeCompletions = completionStore.completions(for: Date())
        return targetAssignments.filter { assignment in
            assignment.kind == .assignment && !badgeCompletions.contains(assignment.id)
        }.count
    }

    var menuBarTitle: String {
        let remaining = remainingAssignmentsCount
        return "Canvas (\(remaining))"
    }

    private var trackableAssignmentsCount: Int {
        allAssignments.filter { $0.kind == .assignment }.count
    }

    private var completedAssignmentsCount: Int {
        allAssignments.filter { $0.kind == .assignment && completedIDs.contains($0.id) }.count
    }
}

private extension AssignmentsViewModel {
    func observeSettings() {
        settings.$configurationVersion
            .sink { [weak self] _ in
                self?.invalidateCache()
                Task { await self?.refresh(reason: .configuration) }
            }
            .store(in: &cancellables)

        settings.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.restartTimer()
            }
            .store(in: &cancellables)
    }

    func restartTimer() {
        timerCancellable?.cancel()
        guard settings.refreshInterval > 0 else { return }
        timerCancellable = Timer.publish(every: settings.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh(reason: .timer) }
            }
    }

    func loadCompletions() {
        completedIDs = completionStore.completions(for: selectedDate)
    }

    func applyFilter() {
        switch filter {
        case .all:
            assignments = allAssignments
        case .assignments:
            assignments = allAssignments.filter { $0.kind == .assignment }
        case .events:
            assignments = allAssignments.filter { $0.kind == .calendarEvent }
        }
    }

    func prepareForNewDate(_ date: Date) {
        selectedDate = date
        loadCompletions()
        errorMessage = nil
        if let cached = cachedAssignments(for: date) {
            allAssignments = cached
            applyFilter()
        } else {
            allAssignments = []
            assignments = []
        }
    }

    func processFetched(_ fetched: [Assignment], for date: Date) {
        allAssignments = fetched.sorted { lhs, rhs in
            let leftDate = lhs.normalizedDueDate ?? .distantFuture
            let rightDate = rhs.normalizedDueDate ?? .distantFuture
            return leftDate < rightDate
        }
        cache(assignments: allAssignments, for: date)
        if Calendar.current.isDateInToday(date) {
            todayAssignments = allAssignments
        }
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            applyFilter()
            loadCompletions()
        }
    }

    func badgeAssignments() -> [Assignment] {
        if Calendar.current.isDate(selectedDate, inSameDayAs: Date()) {
            return allAssignments
        }
        return todayAssignments
    }

    func fetchAssignments(for date: Date, configuration: AssignmentsSourceConfiguration) async throws -> [Assignment] {
        let bounds = Calendar.current.dayBounds(for: date)
        switch configuration {
        case .canvasAPI(let credentials):
            return try await api.fetchAssignments(credentials: credentials, bounds: bounds)
        case .calendarFeed(let url):
            return try await ICSAssignmentsService().fetchAssignments(feedURL: url, bounds: bounds)
        }
    }

    func dayKey(for date: Date) -> String {
        dayFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    func cache(assignments: [Assignment], for date: Date) {
        assignmentCache[dayKey(for: date)] = assignments
    }

    func cachedAssignments(for date: Date) -> [Assignment]? {
        assignmentCache[dayKey(for: date)]
    }

    func prefetchAdjacentDays(from date: Date, configuration: AssignmentsSourceConfiguration) {
        for offset in [-2, -1, 1, 2] {
            guard let target = Calendar.current.date(byAdding: .day, value: offset, to: date) else { continue }
            if cachedAssignments(for: target) != nil { continue }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await fetchAssignments(for: target, configuration: configuration)
                    await MainActor.run {
                        self.cache(assignments: result, for: target)
                        if Calendar.current.isDateInToday(target) {
                            self.todayAssignments = result
                        }
                    }
                } catch {
                    // ignore
                }
            }
        }
    }

    func invalidateCache() {
        assignmentCache.removeAll()
        todayAssignments = []
    }
}
