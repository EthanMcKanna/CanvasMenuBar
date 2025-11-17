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

    struct CourseFilter: Identifiable, Equatable {
        let name: String
        let count: Int

        var id: String { name }
    }

    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedDate: Date
    @Published private(set) var completedIDs: Set<String> = []
    @Published private(set) var courseFilters: [CourseFilter] = []
    @Published var filter: AssignmentFilter {
        didSet {
            defaults.set(filter.rawValue, forKey: filterDefaultsKey)
            applyFilter()
        }
    }
    @Published var selectedCourses: Set<String> = [] {
        didSet {
            if selectedCourses != oldValue {
                applyFilter()
            }
        }
    }

    private let settings: SettingsStore
    private let api: CanvasAPI
    private let completionStore: CompletionStore
    private let icsService: ICSAssignmentsService
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
         defaults: UserDefaults = .standard,
         icsService: ICSAssignmentsService = .shared) {
        self.settings = settings
        self.api = api
        self.completionStore = completionStore
        self.defaults = defaults
        self.icsService = icsService
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

    func refresh(reason: RefreshReason = .manual, forceReloadFeed: Bool? = nil) async {
        let shouldForceFeedReload = forceReloadFeed ?? (reason != .configuration)
        guard let configuration = settings.sourceConfiguration() else {
            assignments = []
            allAssignments = []
            todayAssignments = []
            selectedCourses.removeAll()
            courseFilters = []
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
            let fetched = try await fetchAssignments(for: targetDate, configuration: configuration, forceReloadFeed: shouldForceFeedReload)
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
        Task { await refresh(reason: .configuration, forceReloadFeed: false) }
    }

    func goToToday() {
        prepareForNewDate(Calendar.current.startOfDay(for: Date()))
        Task { await refresh(reason: .configuration, forceReloadFeed: false) }
    }

    func isCompleted(_ assignment: Assignment) -> Bool {
        completedIDs.contains(assignment.id)
    }

    func toggleCompletion(for assignment: Assignment) {
        completedIDs = completionStore.toggle(id: assignment.id, on: selectedDate)
    }

    func toggleCourseFilter(_ name: String) {
        if selectedCourses.contains(name) {
            selectedCourses.remove(name)
        } else {
            selectedCourses.insert(name)
        }
    }

    func clearCourseFilters() {
        guard !selectedCourses.isEmpty else { return }
        selectedCourses.removeAll()
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

    var isFilteringCourses: Bool {
        !selectedCourses.isEmpty
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
    func rebuildCourseFilters() {
        var counts: [String: Int] = [:]
        for assignment in allAssignments {
            let name = assignment.displayCourse
            counts[name, default: 0] += 1
        }
        let sortedNames = counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        courseFilters = sortedNames.compactMap { name in
            guard let count = counts[name] else { return nil }
            return CourseFilter(name: name, count: count)
        }
        let filteredSelection = selectedCourses.filter { counts[$0] != nil }
        if filteredSelection != selectedCourses {
            selectedCourses = filteredSelection
        }
        if counts.isEmpty && !selectedCourses.isEmpty {
            selectedCourses.removeAll()
        }
    }

    func observeSettings() {
        settings.$configurationVersion
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateCache()
                Task {
                    await self.icsService.invalidateCache()
                    await self.refresh(reason: .configuration, forceReloadFeed: true)
                }
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
        var filtered: [Assignment]
        switch filter {
        case .all:
            filtered = allAssignments
        case .assignments:
            filtered = allAssignments.filter { $0.kind == .assignment }
        case .events:
            filtered = allAssignments.filter { $0.kind == .calendarEvent }
        }
        if !selectedCourses.isEmpty {
            filtered = filtered.filter { selectedCourses.contains($0.displayCourse) }
        }
        assignments = filtered
    }

    func prepareForNewDate(_ date: Date) {
        selectedDate = date
        loadCompletions()
        errorMessage = nil
        if let cached = cachedAssignments(for: date) {
            allAssignments = cached
            rebuildCourseFilters()
            applyFilter()
        } else {
            allAssignments = []
            assignments = []
            rebuildCourseFilters()
        }
    }

    func processFetched(_ fetched: [Assignment], for date: Date) {
        allAssignments = fetched.sorted { lhs, rhs in
            let leftDate = lhs.normalizedDueDate ?? .distantFuture
            let rightDate = rhs.normalizedDueDate ?? .distantFuture
            return leftDate < rightDate
        }
        rebuildCourseFilters()
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

    func fetchAssignments(for date: Date, configuration: AssignmentsSourceConfiguration, forceReloadFeed: Bool) async throws -> [Assignment] {
        let bounds = Calendar.current.dayBounds(for: date)
        switch configuration {
        case .canvasAPI(let credentials):
            return try await api.fetchAssignments(credentials: credentials, bounds: bounds)
        case .calendarFeed(let url):
            return try await icsService.fetchAssignments(feedURL: url, bounds: bounds, forceReload: forceReloadFeed)
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
                    let result = try await fetchAssignments(for: target, configuration: configuration, forceReloadFeed: false)
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
        courseFilters = []
        selectedCourses.removeAll()
    }
}
