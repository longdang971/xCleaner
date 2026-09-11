import SwiftUI
import Combine
import AppKit

// MARK: - Tuỳ chọn

final class AppSettings: ObservableObject {
    @AppStorage("moveToTrash")      var moveToTrash: Bool = false
    @AppStorage("oldDownloadDays")  var oldDownloadDays: Int = 60
    @AppStorage("largeMinMB")       var largeMinMB: Int = 50
    @AppStorage("duplicateMinMB")   var duplicateMinMB: Int = 1
    @AppStorage("confirmBeforeClean") var confirmBeforeClean: Bool = true
    @AppStorage("rememberChoices")   var rememberChoices: Bool = true
    @AppStorage("hasSeenWelcome")   var hasSeenWelcome: Bool = false
}

// MARK: - Bộ tiết chế tiến trình

/// Scanner gọi hàm tiến trình hàng nghìn lần mỗi giây. Nếu để mỗi lần đều chạm `@Published`
/// thì SwiftUI dựng lại cây view liên tục và cửa sổ khựng. Bộ này chỉ cho qua tối đa ~20 lần/giây.
final class ProgressThrottle {
    private var lastEmit: CFAbsoluteTime = 0
    private let interval: CFAbsoluteTime

    init(fps: Double = 20) { interval = 1.0 / fps }

    func emit(force: Bool = false, _ block: @escaping () -> Void) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastEmit >= interval else { return }
        lastEmit = now
        DispatchQueue.main.async(execute: block)
    }
}

/// Ứng dụng đang mở mà thao tác sắp tới sẽ đụng tới — chờ người dùng quyết định.
struct PendingQuit: Identifiable, Equatable {
    let id = UUID()
    let bundleID: String
    let name: String
}

// MARK: - Kho kết quả dạng nhóm

@MainActor
final class ScanStore: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    let module: CleanModule
    private let settings: AppSettings

    @Published var phase: Phase = .idle
    @Published var groups: [CleanGroup] = []
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var liveBytes: Int64 = 0
    @Published var outcome: CleanOutcome?
    @Published var lastError: String?
    /// Số mục được đặt lại theo lựa chọn lần trước của người dùng.
    @Published var restoredCount: Int = 0

    /// Các chặng của lần quét đang chạy, để vẽ thành ô.
    @Published var stages: [ScanStage] = []
    @Published var currentStage: Int? = nil
    @Published var stageBytes: [Int: Int64] = [:]
    /// Những mục vừa tìm thấy ở chặng đang chạy, mới nhất ở cuối.
    @Published var found: [CleanedEntry] = []

    @Published var pendingQuit: PendingQuit?
    private var quitQueue: [PendingQuit] = []
    private var pendingCleanGroups: [CleanGroup] = []

    /// Những mục vừa dọn xong, mới nhất ở cuối.
    @Published var cleaned: [CleanedEntry] = []
    @Published var cleanTotal: Int = 0
    @Published var cleanFreed: Int64 = 0

    private let cleanCancel = CancelToken()

    private let cancelToken = CancelToken()
    private let throttle = ProgressThrottle()

    init(module: CleanModule, settings: AppSettings) {
        self.module = module
        self.settings = settings
    }

    // Tổng hợp
    var totalFound: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { groups.reduce(0) { $0 + $1.selectedSize } }
    var selectedItems: [CleanItem] { groups.flatMap { $0.items.filter(\.isSelected) } }
    var needsAdmin: Bool { selectedItems.contains(where: \.requiresAdmin) }

    var ringMode: ScanRing.Mode {
        switch phase {
        case .idle:     return .idle
        case .scanning: return .scanning(progress)
        case .results:  return .results
        case .cleaning: return .cleaning(progress)
        case .done:     return .done
        }
    }

    // MARK: Quét

    func scan() {
        guard phase != .scanning && phase != .cleaning else { return }
        cancelToken.reset()
        phase = .scanning
        groups = []
        progress = 0
        liveBytes = 0
        outcome = nil
        lastError = nil
        statusText = "Đang bắt đầu…"

        let scanner = makeScanner()
        stages = scanner.stages
        currentStage = stages.isEmpty ? nil : 0
        stageBytes = [:]
        found = []
        let token = cancelToken
        let throttle = self.throttle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = scanner.scan(cancel: token) { p in
                if let name = p.foundName, p.foundBytes > 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.found.append(CleanedEntry(name: name, bytes: p.foundBytes))
                        if self.found.count > 60 { self.found.removeFirst(self.found.count - 60) }
                    }
                }
                throttle.emit {
                    guard let self else { return }
                    self.progress = p.fraction
                    self.statusText = p.message
                    if p.bytesFound > 0 { self.liveBytes = p.bytesFound }
                    if self.currentStage != p.stageIndex {
                        self.currentStage = p.stageIndex
                        self.found = []          // sang chặng khác thì danh sách bắt đầu lại
                    }
                    if self.stageBytes != p.stageBytes { self.stageBytes = p.stageBytes }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                var g = result
                var restored = SelectionMemory.shared.apply(to: &g)

                // Nếu ghi nhớ cũ làm cho không còn mục nào được chọn thì bỏ nó đi. Không ai
                // muốn quét xong rồi nhìn một màn hình trắng trơn với nút Dọn mờ tịt, kể cả
                // người đã từng bấm "bỏ chọn tất cả" ở lần trước.
                let defaultHasSelection = result.contains { $0.items.contains(where: \.defaultSelected) }
                if restored > 0, defaultHasSelection, g.allSatisfy({ $0.selectedCount == 0 }) {
                    SelectionMemory.shared.forget(g.flatMap(\.items))
                    g = result
                    restored = 0
                }
                withAnimation(Motion.standard) {
                    self.restoredCount = restored
                    self.groups = g
                    self.liveBytes = g.reduce(0) { $0 + $1.totalSize }
                    self.phase = token.isCancelled && g.isEmpty ? .idle : .results
                    self.progress = 1
                    self.statusText = g.isEmpty ? "Không tìm thấy gì để dọn" : "Sẵn sàng dọn"
                }
            }
        }
    }

    func cancelScan() {
        cancelToken.cancel()
        statusText = "Đang dừng…"
    }

    /// Dừng giữa chừng khi đang dọn. Phần đã xoá thì vẫn là đã xoá.
    func cancelClean() {
        cleanCancel.cancel()
        statusText = "Đang dừng…"
    }

    /// Chỉ còn Quét thông minh dùng màn hình dạng nhóm; nó tự gọi các bộ quét con bên trong.
    private func makeScanner() -> ModuleScanner { SmartScanScanner() }

    // MARK: Chọn

    func toggleItem(groupID: String, itemID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }),
              let ii = groups[gi].items.firstIndex(where: { $0.id == itemID }) else { return }
        groups[gi].items[ii].isSelected.toggle()
        SelectionMemory.shared.record(groups[gi].items[ii])
    }

    func toggleGroup(_ groupID: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let turnOn = groups[gi].selection != .all
        for i in groups[gi].items.indices { groups[gi].items[i].isSelected = turnOn }
        SelectionMemory.shared.record(groups[gi].items)
    }

    /// Bật/tắt cả một phần trong nhóm (ví dụ toàn bộ "Cookie & đăng nhập").
    func toggleCategory(groupID: String, category: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let turnOn = groups[gi].selection(in: category) != .all
        for i in groups[gi].items.indices where groups[gi].items[i].category == category {
            groups[gi].items[i].isSelected = turnOn
        }
        SelectionMemory.shared.record(groups[gi].items.filter { $0.category == category })
    }

    func toggleExpanded(_ groupID: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        withAnimation(Motion.standard) { groups[gi].isExpanded.toggle() }
    }

    /// Thoát ứng dụng đang giữ dữ liệu (trình duyệt) để việc dọn không bị ghi đè ngay sau đó.
    func quitApp(groupID: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }),
              let bid = groups[gi].runningBundleID else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        running.forEach { $0.terminate() }

        // Cho app vài giây để đóng, rồi kiểm tra lại thay vì tin ngay vào terminate().
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self,
                  let gi = self.groups.firstIndex(where: { $0.id == groupID }) else { return }
            if !FileUtils.isRunning(bundleID: bid) {
                withAnimation(Motion.gentle) {
                    self.groups[gi].runningBundleID = nil
                    self.groups[gi].subtitle = "\(self.groups[gi].items.count) mục"
                }
            }
        }
    }

    func selectAll(_ on: Bool) {
        for gi in groups.indices {
            for ii in groups[gi].items.indices { groups[gi].items[ii].isSelected = on }
        }
        // Chọn/bỏ chọn tất cả là thao tác nhất thời, không phải ý định lâu dài về từng mục:
        // ghi nhớ nó thì lần quét sau mọi thứ im lìm không chọn gì và người dùng chẳng hiểu vì sao.
        // Nhân tiện xoá luôn ghi nhớ cũ để lần sau quay về đúng đề xuất mặc định.
        SelectionMemory.shared.forget(groups.flatMap(\.items))
        restoredCount = 0
    }

    // MARK: Dọn

    /// - Parameter groupID: chỉ dọn nhóm này; bỏ trống thì dọn mọi thứ đang được chọn.
    func clean(groupID: String? = nil) {
        // Xếp theo nhóm để lúc dọn, các ô lần lượt sáng lên đúng thứ tự người dùng nhìn thấy.
        let sourceGroups = groupID == nil
            ? groups.filter { $0.items.contains(where: \.isSelected) }
            : groups.filter { $0.id == groupID && $0.items.contains(where: \.isSelected) }
        guard !sourceGroups.isEmpty else { return }

        // Ứng dụng nào đang mở mà lần dọn này sẽ đụng vào? Hỏi trước, rồi mới xoá.
        let running = Self.runningApps(in: sourceGroups)
        if !running.isEmpty {
            pendingCleanGroups = sourceGroups
            quitQueue = Array(running.dropFirst())
            pendingQuit = running.first
            return
        }
        startCleaning(sourceGroups)
    }

    /// Người dùng chọn thoát ứng dụng rồi dọn tiếp.
    func quitPendingApp() {
        guard let pending = pendingQuit else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: pending.bundleID)
            .forEach { $0.terminate() }
        // Cho app một nhịp để đóng hẳn; không chờ thì tệp vừa xoá lại bị ghi đè ngay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.advanceQuitQueue()
        }
    }

    /// Người dùng chọn dừng: không dọn gì cả.
    func cancelPendingQuit() {
        pendingQuit = nil
        quitQueue = []
        pendingCleanGroups = []
    }

    private func advanceQuitQueue() {
        if let next = quitQueue.first {
            quitQueue.removeFirst()
            pendingQuit = next
            return
        }
        let groups = pendingCleanGroups
        pendingQuit = nil
        pendingCleanGroups = []
        guard !groups.isEmpty else { return }
        startCleaning(groups)
    }

    private static func runningApps(in groups: [CleanGroup]) -> [PendingQuit] {
        var seen = Set<String>()
        var result: [PendingQuit] = []
        for g in groups {
            var ids: [String] = g.categoryAppIDs.values.map { $0 }
            if let b = g.runningBundleID { ids.append(b) }
            if let b = g.appBundleID { ids.append(b) }
            for id in ids where !seen.contains(id) && FileUtils.isRunning(bundleID: id) {
                seen.insert(id)
                result.append(PendingQuit(bundleID: id,
                                          name: AppCatalog.shared.name(forBundleID: id) ?? id))
            }
        }
        return result
    }

    private func startCleaning(_ sourceGroups: [CleanGroup]) {
        var ordered: [CleanItem] = []
        var stageOfPath: [String: Int] = [:]
        for (i, g) in sourceGroups.enumerated() {
            for item in g.items where item.isSelected {
                stageOfPath[item.url.path] = i
                ordered.append(item)
            }
        }

        phase = .cleaning
        progress = 0
        statusText = "Đang dọn…"
        cleaned = []
        cleanTotal = ordered.count
        cleanFreed = 0
        cleanCancel.reset()
        stages = sourceGroups.map {
            ScanStage(id: $0.id, title: $0.title, icon: $0.icon, appBundleID: $0.appBundleID)
        }
        currentStage = 0
        stageBytes = [:]

        let request = Remover.Request(
            items: ordered,
            moveToTrash: settings.moveToTrash,
            adminPrompt: "xCleaner cần quyền quản trị để xoá \(ordered.filter(\.requiresAdmin).count) mục trong thư mục hệ thống.",
            cancel: cleanCancel)
        let throttle = ProgressThrottle(fps: 15)
        var perStage: [Int: Int64] = [:]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Remover.perform(request, progress: { fraction, message in
                throttle.emit {
                    guard let self else { return }
                    self.progress = fraction
                    self.statusText = message
                }
            }, itemFinished: { item, ok in
                let idx = stageOfPath[item.url.path] ?? 0
                if ok { perStage[idx, default: 0] += item.size }
                let snapshot = perStage
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Sang ô khác thì chốt ô cũ lại — nó sẽ thu về và hiện số đã dọn.
                    if self.currentStage != idx {
                        if let old = self.currentStage {
                            self.stageBytes[old] = snapshot[old] ?? 0
                        }
                        withAnimation(Motion.standard) { self.currentStage = idx }
                    }
                    self.cleaned.append(CleanedEntry(name: item.name, bytes: item.size,
                                                     failed: !ok, stageIndex: idx))
                    if ok { self.cleanFreed += item.size }
                    if self.cleaned.count > 400 { self.cleaned.removeFirst(200) }
                }
            })
            DispatchQueue.main.async {
                guard let self else { return }
                for (i, v) in perStage where self.stageBytes[i] == nil { self.stageBytes[i] = v }
                if let last = self.currentStage, self.stageBytes[last] == nil {
                    self.stageBytes[last] = perStage[last] ?? 0
                }
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.phase = .done
                    self.progress = 1
                    self.currentStage = nil
                    self.statusText = result.wasCancelled && result.removedCount == 0
                        ? "Đã huỷ" : "Đã dọn xong"
                    let removed = Set(ordered.map(\.url.path))
                    for gi in self.groups.indices {
                        self.groups[gi].items.removeAll {
                            removed.contains($0.url.path) && !FileUtils.exists($0.url)
                        }
                    }
                    self.groups.removeAll { $0.items.isEmpty }
                    self.liveBytes = result.freedBytes
                }
            }
        }
    }

    /// Bỏ kết quả và quay về màn khởi đầu, như chưa từng quét.
    func backToStart() {
        cancelToken.cancel()
        withAnimation(Motion.standard) {
            groups = []
            outcome = nil
            restoredCount = 0
            progress = 0
            liveBytes = 0
            statusText = ""
            stages = []
            currentStage = nil
            stageBytes = [:]
            found = []
            phase = .idle
        }
    }

    #if DEBUG
    /// Dựng hộp thoại "ứng dụng đang mở" để xem giao diện — không dọn gì cả.
    func debugShowQuitDialog() {
        let running = Self.runningApps(in: groups)
        pendingQuit = running.first
            ?? PendingQuit(bundleID: "com.google.Chrome", name: "Google Chrome")
    }

    /// Dựng màn "đang dọn" bằng dữ liệu giả để xem giao diện — không xoá bất cứ thứ gì.
    func debugDemoClean() {
        let src = groups.filter { $0.items.contains(where: \.isSelected) }
        guard !src.isEmpty else { return }
        var plan: [(Int, CleanItem)] = []
        for (i, g) in src.enumerated() {
            for item in g.items.filter(\.isSelected).prefix(8) { plan.append((i, item)) }
        }
        cleaned = []
        cleanTotal = plan.count
        cleanFreed = 0
        stages = src.map { ScanStage(id: $0.id, title: $0.title, icon: $0.icon,
                                     appBundleID: $0.appBundleID) }
        stageBytes = [:]
        currentStage = 0
        phase = .cleaning

        var acc: [Int: Int64] = [:]
        for (n, entry) in plan.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22 * Double(n)) { [weak self] in
                guard let self else { return }
                let (idx, item) = entry
                if self.currentStage != idx {
                    if let old = self.currentStage { self.stageBytes[old] = acc[old] ?? 0 }
                    withAnimation(Motion.standard) { self.currentStage = idx }
                }
                acc[idx, default: 0] += item.size
                self.cleanFreed += item.size
                self.cleaned.append(CleanedEntry(name: item.name, bytes: item.size,
                                                 stageIndex: idx))
                self.progress = Double(n + 1) / Double(plan.count)
            }
        }
    }
    #endif

    func reset() {
        phase = groups.isEmpty ? .idle : .results
        outcome = nil
        progress = groups.isEmpty ? 0 : 1
        liveBytes = groups.reduce(0) { $0 + $1.totalSize }
        statusText = groups.isEmpty ? "" : "Sẵn sàng dọn"
    }
}

// MARK: - Gỡ ứng dụng

@MainActor
final class UninstallStore: ObservableObject {
    @Published var apps: [UninstallScanner.InstalledApp] = []
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var search = ""
    @Published var showSystemApps = false
    @Published var sort: Sort = .size

    @Published var selectedApp: UninstallScanner.InstalledApp?
    @Published var leftovers: [CleanItem] = []
    @Published var isLoadingLeftovers = false
    @Published var outcome: CleanOutcome?
    @Published var isRemoving = false

    enum Sort: String, CaseIterable, Identifiable {
        case size = "Dung lượng", name = "Tên", lastUsed = "Lần dùng cuối"
        var id: String { rawValue }
    }

    private let settings: AppSettings
    private let scanner = UninstallScanner()
    private let cancelToken = CancelToken()
    private let throttle = ProgressThrottle()

    init(settings: AppSettings) { self.settings = settings }

    var filteredApps: [UninstallScanner.InstalledApp] {
        var list = apps
        if !showSystemApps { list = list.filter { !$0.isSystemApp } }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .size:     list.sort { $0.totalSize > $1.totalSize }
        case .name:     list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    var selectedLeftoverSize: Int64 { leftovers.filter(\.isSelected).reduce(0) { $0 + $1.size } }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        cancelToken.reset()
        statusText = "Đang đọc danh sách ứng dụng…"
        let token = cancelToken
        let throttle = self.throttle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = UninstallScanner().listApps(cancel: token) { p in
                throttle.emit {
                    self?.progress = p.fraction
                    self?.statusText = p.message
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.apps = result
                    self.isLoading = false
                    self.statusText = "\(result.count) ứng dụng"
                }
            }
        }
    }

    func backToStart() {
        cancelToken.cancel()
        withAnimation(Motion.standard) {
            apps = []
            selectedApp = nil
            leftovers = []
            outcome = nil
            search = ""
            statusText = ""
        }
    }

    func select(_ app: UninstallScanner.InstalledApp) {
        selectedApp = app
        leftovers = []
        outcome = nil
        isLoadingLeftovers = true
        let token = cancelToken
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = UninstallScanner().leftovers(for: app, cancel: token)
            DispatchQueue.main.async {
                guard let self, self.selectedApp?.url == app.url else { return }
                withAnimation(Motion.gentle) {
                    self.leftovers = items
                    self.isLoadingLeftovers = false
                }
            }
        }
    }

    func toggle(_ id: UUID) {
        guard let i = leftovers.firstIndex(where: { $0.id == id }) else { return }
        leftovers[i].isSelected.toggle()
    }

    @Published var pendingQuit: PendingQuit?

    func uninstall() {
        guard let app = selectedApp, leftovers.contains(where: \.isSelected) else { return }
        // Gỡ một ứng dụng đang chạy thì nó còn ghi lại tuỳ chọn lúc thoát, và tệp vừa xoá
        // quay về như chưa có chuyện gì.
        if FileUtils.isRunning(bundleID: app.id) {
            pendingQuit = PendingQuit(bundleID: app.id, name: app.name)
            return
        }
        performUninstall()
    }

    func quitPendingApp() {
        guard let pending = pendingQuit else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: pending.bundleID)
            .forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.pendingQuit = nil
            self?.performUninstall()
        }
    }

    func cancelPendingQuit() { pendingQuit = nil }

    private func performUninstall() {
        let items = leftovers.filter(\.isSelected)
        guard !items.isEmpty, let app = selectedApp else { return }
        isRemoving = true

        let request = Remover.Request(
            items: items,
            moveToTrash: settings.moveToTrash,
            adminPrompt: "xCleaner cần quyền quản trị để gỡ \(app.name) khỏi thư mục hệ thống.")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Remover.perform(request) { _, _ in }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.isRemoving = false
                    self.leftovers.removeAll { !FileUtils.exists($0.url) }
                    if !FileUtils.exists(app.url) {
                        self.apps.removeAll { $0.url == app.url }
                        self.selectedApp = nil
                    }
                }
            }
        }
    }
}

// MARK: - Tệp lớn & cũ

@MainActor
final class LargeOldStore: ObservableObject {
    @Published var files: [LargeOldScanner.Found] = []
    @Published var selected: Set<URL> = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var filter: Filter = .all
    @Published var search = ""
    @Published var outcome: CleanOutcome?
    @Published var roots: [URL] = [FileUtils.home]

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tất cả", old = "Lâu không dùng", video = "Video", archive = "Nén / bộ cài"
        var id: String { rawValue }
    }

    private let settings: AppSettings
    private let cancelToken = CancelToken()
    private let throttle = ProgressThrottle()

    init(settings: AppSettings) { self.settings = settings }

    var visibleFiles: [LargeOldScanner.Found] {
        var list = files
        switch filter {
        case .all:     break
        case .old:     list = list.filter(\.isOld)
        case .video:   list = list.filter { $0.kind == "Video" }
        case .archive: list = list.filter { $0.kind == "Nén / bộ cài" }
        }
        if !search.isEmpty {
            list = list.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        }
        return list
    }

    var selectedSize: Int64 {
        files.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        guard !isScanning else { return }
        cancelToken.reset()
        isScanning = true
        files = []
        selected = []
        outcome = nil
        progress = 0

        var opts = LargeOldScanner.Options()
        opts.roots = roots
        opts.minimumSize = Int64(settings.largeMinMB) * 1024 * 1024
        let token = cancelToken
        let throttle = self.throttle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = LargeOldScanner().scan(options: opts, cancel: token) { p in
                throttle.emit {
                    self?.progress = p.fraction
                    self?.statusText = p.message
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.files = result
                    self.isScanning = false
                    self.progress = 1
                    self.statusText = "\(result.count) tệp lớn hơn \(self.settings.largeMinMB) MB"
                }
            }
        }
    }

    func cancel() { cancelToken.cancel() }

    func backToStart() {
        cancelToken.cancel()
        withAnimation(Motion.standard) {
            files = []
            selected = []
            outcome = nil
            progress = 0
            statusText = ""
        }
    }

    func toggle(_ url: URL) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    func remove() {
        let items = files.filter { selected.contains($0.url) }
            .map { CleanItem(url: $0.url, detail: "", size: $0.size,
                             requiresAdmin: PrivilegedRunner.needsAdmin(for: $0.url),
                             isDirectory: FileUtils.isDirectory($0.url)) }
        guard !items.isEmpty else { return }

        // Tệp cá nhân luôn vào Thùng rác để còn lấy lại được.
        let request = Remover.Request(items: items, moveToTrash: true,
                                      adminPrompt: "xCleaner cần quyền quản trị để xoá các tệp đã chọn.")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Remover.perform(request) { _, _ in }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.files.removeAll { !FileUtils.exists($0.url) }
                    self.selected = []
                }
            }
        }
    }
}

// MARK: - Tệp trùng lặp

@MainActor
final class DuplicateStore: ObservableObject {
    @Published var sets: [DuplicateScanner.DuplicateSet] = []
    @Published var selected: Set<URL> = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var outcome: CleanOutcome?
    @Published var roots: [URL] = DuplicateScanner.Options().roots.filter { FileUtils.exists($0) }

    private let settings: AppSettings
    private let cancelToken = CancelToken()
    private let throttle = ProgressThrottle()

    init(settings: AppSettings) { self.settings = settings }

    var reclaimable: Int64 { sets.reduce(0) { $0 + $1.reclaimable } }
    var selectedSize: Int64 {
        sets.reduce(0) { acc, s in acc + s.size * Int64(s.files.filter { selected.contains($0) }.count) }
    }

    func scan() {
        guard !isScanning else { return }
        cancelToken.reset()
        isScanning = true
        sets = []
        selected = []
        outcome = nil
        progress = 0

        var opts = DuplicateScanner.Options()
        opts.roots = roots
        opts.minimumSize = Int64(settings.duplicateMinMB) * 1024 * 1024
        let token = cancelToken
        let throttle = self.throttle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = DuplicateScanner().scan(options: opts, cancel: token) { p in
                throttle.emit {
                    self?.progress = p.fraction
                    self?.statusText = p.message
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.sets = result
                    self.isScanning = false
                    self.progress = 1
                    self.statusText = result.isEmpty
                        ? "Không tìm thấy tệp trùng"
                        : "\(result.count) nhóm trùng lặp"
                    self.autoSelect()
                }
            }
        }
    }

    func cancel() { cancelToken.cancel() }

    func backToStart() {
        cancelToken.cancel()
        withAnimation(Motion.standard) {
            sets = []
            selected = []
            outcome = nil
            progress = 0
            statusText = ""
        }
    }

    /// Giữ lại bản nằm ở đường dẫn ngắn nhất, chọn các bản còn lại.
    func autoSelect() {
        var s = Set<URL>()
        for set in sets {
            let sorted = set.files.sorted { $0.path.count < $1.path.count }
            for f in sorted.dropFirst() { s.insert(f) }
        }
        selected = s
    }

    func toggle(_ url: URL, in set: DuplicateScanner.DuplicateSet) {
        if selected.contains(url) {
            selected.remove(url)
        } else {
            // Không cho phép chọn hết cả nhóm — phải còn lại ít nhất một bản.
            let chosen = set.files.filter { selected.contains($0) }.count
            guard chosen < set.files.count - 1 else { return }
            selected.insert(url)
        }
    }

    func remove() {
        let items = sets.flatMap { set in
            set.files.filter { selected.contains($0) }
                .map { CleanItem(url: $0, detail: "", size: set.size, isDirectory: false) }
        }
        guard !items.isEmpty else { return }
        let request = Remover.Request(items: items, moveToTrash: true,
                                      adminPrompt: "xCleaner cần quyền quản trị để xoá các tệp đã chọn.")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Remover.perform(request) { _, _ in }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.selected = []
                    for i in self.sets.indices {
                        self.sets[i].files.removeAll { !FileUtils.exists($0) }
                    }
                    self.sets.removeAll { $0.files.count < 2 }
                }
            }
        }
    }
}

// MARK: - Trạng thái chung

@MainActor
final class AppState: ObservableObject {
    @Published var module: CleanModule = .smartScan
    @Published var showSettings = false
    let settings = AppSettings()

    private var scanStores: [CleanModule: ScanStore] = [:]
    lazy var uninstall = UninstallStore(settings: settings)
    lazy var largeOld = LargeOldStore(settings: settings)
    lazy var duplicates = DuplicateStore(settings: settings)

    func scanStore(for module: CleanModule) -> ScanStore {
        if let s = scanStores[module] { return s }
        let s = ScanStore(module: module, settings: settings)
        scanStores[module] = s
        return s
    }
}
