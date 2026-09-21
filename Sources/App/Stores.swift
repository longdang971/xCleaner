import SwiftUI
import Combine
import AppKit

// MARK: - Tuỳ chọn

final class AppSettings: ObservableObject {
    @AppStorage("moveToTrash")      var moveToTrash: Bool = false
    @AppStorage("oldDownloadDays")  var oldDownloadDays: Int = 60
    @AppStorage("largeMinMB")       var largeMinMB: Int = 50
    @AppStorage("duplicateMinMB")   var duplicateMinMB: Int = 1
    @AppStorage("rememberChoices")   var rememberChoices: Bool = true
    @AppStorage("hasSeenWelcome")   var hasSeenWelcome: Bool = false
    /// Trực Thùng rác để mời dọn tàn dư khi người dùng tự xoá một ứng dụng. Mặc định BẬT.
    @AppStorage("smartDelete")      var smartDelete: Bool = true
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

/// Kéo vòng tiến trình đi mượt.
///
/// Bộ quét chỉ biết mình đang ở chặng nào, nên con số thật nhảy từng nấc to đùng — năm chặng
/// là năm cú giật 20%. Lớp này giữ hai mốc: `target` là nấc thật vừa nhận, `ceiling` là trần
/// của chặng đang chạy (luôn thấp hơn nấc kế tiếp). Mỗi nhịp 1/60 giây nó kéo giá trị hiển thị
/// tới `target` thật nhanh rồi bò chậm dần về `ceiling` trong lúc chờ nấc sau. Vòng tròn nhờ đó
/// không bao giờ đứng im, cũng không bao giờ vượt quá phần việc đã thật sự xong.
@MainActor
final class ProgressSmoother {
    private var value: Double = 0
    private var target: Double = 0
    private var ceiling: Double = 0
    private var timer: Timer?
    private let onChange: (Double) -> Void

    /// Đuổi kịp nấc thật trong khoảng một phần năm giây.
    private let catchUp = 0.18
    /// Nhưng không quá nửa vòng mỗi giây: một chặng ngắn xong cái rụp làm nấc thật vọt lên
    /// cả mấy chục phần trăm, để nguyên thì vòng tròn lại giật đúng như cũ.
    private let maxStep = 0.5 / 60.0
    /// Bò trong chặng: tiệm cận trần với hằng số thời gian khoảng 1,4 giây.
    private let creep = 0.012

    init(onChange: @escaping (Double) -> Void) { self.onChange = onChange }

    deinit { timer?.invalidate() }

    func reset() {
        stop()
        value = 0; target = 0; ceiling = 0
        onChange(0)
    }

    /// Nấc thật vừa nhận, kèm trần được phép bò tới trong lúc chờ nấc sau.
    func report(_ fraction: Double, ceiling limit: Double) {
        target = max(target, min(1, fraction))
        ceiling = max(ceiling, max(min(1, limit), target))
        start()
    }

    /// Xong hẳn — màn hình đã chuyển, không việc gì phải bò nốt cho đẹp.
    func complete() {
        stop()
        value = 1; target = 1; ceiling = 1
        onChange(1)
    }

    private func start() {
        guard timer == nil else { return }
        // `[weak self]` phải nằm ở closure của Timer: đặt nó ở closure bên trong thì closure
        // ngoài vẫn giữ self để dựng closure trong, và cái timer sống mãi cùng cái store.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick()
            }
        }
        // Chế độ .common để vòng tròn không đứng hình khi người dùng đang kéo cửa sổ.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let before = value
        if value < target {
            let step = min(max((target - value) * catchUp, 0.0012), maxStep)
            value = min(target, value + step)
        } else if value < ceiling {
            value += (ceiling - value) * creep
        } else {
            stop()                     // đã chạm trần, chờ nấc sau đánh thức
            return
        }
        if value != before { onChange(value) }
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
    private lazy var smoother = ProgressSmoother { [weak self] v in self?.progress = v }

    init(module: CleanModule, settings: AppSettings) {
        self.module = module
        self.settings = settings
    }

    // Tổng hợp
    /// Lần quét có tìm ra thứ gì đáng để người dùng động tay không.
    /// Không dùng `groups.isEmpty` được nữa: Quét thông minh luôn trả về đủ năm thẻ, thẻ nào
    /// không có gì thì rỗng chứ không biến mất.
    var hasResults: Bool { groups.contains { !$0.items.isEmpty || $0.needsFullDiskAccess } }
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
        smoother.reset()
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
            // Quên những mục đã biến mất, và quên sạch nếu mức quyền của app vừa đổi.
            UndeletableMemory.shared.refresh()
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
                    self.smoother.report(p.fraction, ceiling: p.ceiling)
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
                let foundSomething = g.contains { !$0.items.isEmpty || $0.needsFullDiskAccess }
                withAnimation(Motion.standard) {
                    self.restoredCount = restored
                    self.groups = g
                    self.liveBytes = g.reduce(0) { $0 + $1.totalSize }
                    self.phase = token.isCancelled && !foundSomething ? .idle : .results
                    self.smoother.complete()
                    self.statusText = foundSomething ? "Sẵn sàng dọn" : "Không tìm thấy gì để dọn"
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

    /// Dọn mọi thứ đang được chọn ở tất cả các thẻ.
    ///
    /// Cố ý không có đường dọn riêng một thẻ: trang chi tiết từng có nút "Dọn" giống hệt nút
    /// ngoài lưới nhưng chỉ dọn thẻ đang xem. Bấm vào thân thẻ là lọt vào trang đó, bấm "Dọn"
    /// thì chỉ mỗi Nhật ký được dọn và người dùng tưởng app hỏng.
    func clean() {
        // Xếp theo nhóm để lúc dọn, các ô lần lượt sáng lên đúng thứ tự người dùng nhìn thấy.
        let sourceGroups = groups.filter { $0.items.contains(where: \.isSelected) }
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
            guard let self else { return }
            // `terminate()` chỉ là lời đề nghị: app còn tài liệu chưa lưu sẽ hiện hộp hỏi
            // và ở lại. Dọn lúc đó thì nó ghi đè lại đúng thứ vừa xoá — nên giữ nguyên hộp
            // thoại để người dùng xử lý xong rồi bấm lại.
            guard !FileUtils.isRunning(bundleID: pending.bundleID) else { return }
            self.advanceQuitQueue()
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

    /// Bundle id của những ứng dụng mà **lần dọn này thật sự đụng vào dữ liệu của chúng**,
    /// theo đúng thứ tự người dùng nhìn thấy. Không hỏi thoát ứng dụng nào ngoài danh sách này.
    ///
    /// Thẻ "Trình duyệt" gộp mọi trình duyệt vào một nhóm, mỗi cái là một *phần* riêng
    /// (`categoryAppIDs`). Trước đây chỉ cần nhóm có một mục được chọn là app của **mọi** phần
    /// bị đem ra hỏi — bỏ chọn sạch phần của Chrome mà vẫn bị bắt đóng Chrome để dọn Safari.
    /// Nên chỉ lấy app của những phần đang có mục được chọn; mục không thuộc phần nào thì mới
    /// rơi về app của cả nhóm.
    static func appIDsToQuit(in groups: [CleanGroup]) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        func add(_ id: String?) {
            guard let id, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        for g in groups {
            for item in g.items where item.isSelected {
                if let bid = g.categoryAppIDs[item.category] {
                    add(bid)
                } else {
                    add(g.runningBundleID)
                    add(g.appBundleID)
                }
            }
        }
        return ids
    }

    private static func runningApps(in groups: [CleanGroup]) -> [PendingQuit] {
        appIDsToQuit(in: groups)
            .filter { FileUtils.isRunning(bundleID: $0) }
            .map { PendingQuit(bundleID: $0,
                               name: AppCatalog.shared.name(forBundleID: $0) ?? $0) }
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
        smoother.reset()
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
                    // Lúc dọn thì mốc thật đã mịn sẵn (từng mục một), chỉ cần nội suy giữa
                    // hai mốc chứ không phải bò thêm.
                    self.smoother.report(fraction, ceiling: fraction)
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
                CleanLedger.shared.record(result.freedBytes)
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.phase = .done
                    self.smoother.complete()
                    self.currentStage = nil
                    self.statusText = result.wasCancelled && result.removedCount == 0
                        ? "Đã huỷ" : "Đã dọn xong"
                    // Bỏ khỏi danh sách những mục đã thật sự sạch. Mục "dọn ruột" giữ lại
                    // chính thư mục nên `exists` vẫn đúng — phải hỏi xem nó còn gì bên trong
                    // không, nếu không quay lại màn kết quả vẫn thấy nguyên danh sách cũ.
                    let removed = Set(ordered.map(\.url.path))
                    for gi in self.groups.indices {
                        self.groups[gi].items.removeAll {
                            removed.contains($0.url.path) && Remover.isCleared($0)
                        }
                    }
                    // Thẻ rỗng thì ở lại: năm thẻ của Quét thông minh luôn có mặt.
                    self.liveBytes = result.freedBytes
                }
            }
        }
    }

    /// Bỏ kết quả và quay về màn khởi đầu, như chưa từng quét.
    func backToStart() {
        cancelToken.cancel()
        smoother.reset()
        withAnimation(Motion.standard) {
            groups = []
            outcome = nil
            restoredCount = 0
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
    /// Làm rỗng vài thẻ để xem bố cục lúc một mục không tìm thấy gì. Đi đường thật thì phải
    /// có sẵn một máy đã sạch đúng mấy mục đó mới nhìn được.
    func debugEmptyCards(_ ids: [String]) {
        withAnimation(Motion.standard) {
            for gi in groups.indices where ids.contains(groups[gi].id) {
                groups[gi].items = []
                groups[gi].needsFullDiskAccess = false
            }
        }
    }

    /// Dựng hộp thoại "ứng dụng đang mở" để xem giao diện — không dọn gì cả.
    func debugShowQuitDialog() {
        let running = Self.runningApps(in: groups)
        pendingQuit = running.first
            ?? PendingQuit(bundleID: "com.google.Chrome", name: "Google Chrome")
    }

    /// Dựng thẳng màn "đã dọn xong" bằng dữ liệu giả — không quét, không xoá gì cả.
    /// Cần khi xem lại bố cục màn này: đi đường thật phải chờ hết một lần quét.
    /// `variant`: `"cancel"` dựng cảnh huỷ giữa chừng chưa xoá được gì, `"empty"` dựng cảnh dọn
    /// xong mà không đòi lại được byte nào. Hai nhánh này của màn dọn xong không có đường nào
    /// khác để xem bằng mắt — muốn gặp thật thì phải bấm huỷ đúng lúc đang hỏi mật khẩu.
    func debugDemoDone(variant: String = "1") {
        let demo: [(String, String, Int64)] = [
            ("Bộ nhớ đệm hệ thống", "internaldrive", 6_900_000_000),
            ("Thùng rác", "trash", 3_100_000_000),
            ("Tệp tải về cũ", "arrow.down.circle", 1_400_000_000),
            ("Nhật ký & báo cáo sự cố", "doc.text", 620_000_000),
            ("Dấu vết trình duyệt", "safari", 260_000_000)
        ]
        stages = demo.enumerated().map {
            ScanStage(id: "demo\($0.offset)", title: $0.element.0, icon: $0.element.1)
        }
        stageBytes = Dictionary(uniqueKeysWithValues: demo.enumerated().map { ($0.offset, $0.element.2) })
        currentStage = nil
        switch variant {
        case "cancel":
            outcome = CleanOutcome(removedCount: 0, trashedCount: 0, freedBytes: 0,
                                   failures: [], wasCancelled: true, usedAdmin: false)
        case "empty":
            outcome = CleanOutcome(removedCount: 0, trashedCount: 0, freedBytes: 0,
                                   failures: [], wasCancelled: false, usedAdmin: false)
        default:
            outcome = CleanOutcome(removedCount: 264, trashedCount: 0,
                                   freedBytes: demo.reduce(0) { $0 + $1.2 },
                                   failures: [], wasCancelled: false, usedAdmin: true)
        }
        statusText = "Đã dọn xong"
        smoother.complete()
        phase = .done
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
                let f = Double(n + 1) / Double(plan.count)
                self.smoother.report(f, ceiling: f)
            }
        }

        // Chạy nốt sang màn "xong" để xem được cả hai màn trong một lần mở.
        let freed = plan.reduce(Int64(0)) { $0 + $1.1.size }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22 * Double(plan.count) + 0.6) {
            [weak self] in
            guard let self, self.phase == .cleaning else { return }
            for (i, _) in self.stages.enumerated() where self.stageBytes[i] == nil {
                self.stageBytes[i] = acc[i] ?? 0
            }
            withAnimation(Motion.standard) {
                self.outcome = CleanOutcome(removedCount: plan.count, trashedCount: 0,
                                            freedBytes: freed, failures: [],
                                            wasCancelled: false, usedAdmin: true)
                self.phase = .done
                self.smoother.complete()
                self.currentStage = nil
                self.statusText = "Đã dọn xong"
            }
        }
    }
    #endif

    func reset() {
        let found = hasResults
        phase = found ? .results : .idle
        outcome = nil
        if found { smoother.complete() } else { smoother.reset() }
        liveBytes = groups.reduce(0) { $0 + $1.totalSize }
        statusText = found ? "Sẵn sàng dọn" : ""
    }
}


// MARK: - Mục khởi động cùng máy

@MainActor
final class StartupStore: ObservableObject {
    @Published var items: [StartupScanner.Item] = []
    @Published var isLoading = false
    @Published var statusText = ""
    @Published var search = ""
    @Published var filter: Filter = .thirdParty
    @Published var lastError: String?
    /// Mục đang chờ macOS trả lời — để khoá công tắc, tránh bấm hai lần.
    @Published var working: Set<String> = []
    @Published var pendingRemoval: StartupScanner.Item?

    enum Filter: String, CaseIterable, Identifiable {
        case thirdParty = "Của ứng dụng"
        case all = "Tất cả"
        case disabled = "Đang tắt"
        case orphan = "Không còn dùng"
        var id: String { rawValue }
    }

    private let settings: AppSettings
    private let cancelToken = CancelToken()
    // Màn này không có vòng tiến trình — chỉ một dòng chữ — nên không cần bộ nội suy 60 khung
    // mỗi giây; để nguyên thì cả trang dựng lại liên tục suốt lúc đọc mà chẳng ai thấy gì.
    private let throttle = ProgressThrottle()

    init(settings: AppSettings) { self.settings = settings }

    var visibleItems: [StartupScanner.Item] {
        var list = items
        switch filter {
        case .thirdParty: list = list.filter { !$0.isApple }
        case .all:        break
        case .disabled:   list = list.filter(\.isDisabled)
        case .orphan:     list = list.filter(\.isOrphan)
        }
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.label.localizedCaseInsensitiveContains(search)
            }
        }
        return list
    }

    var activeCount: Int { items.filter { !$0.isApple && !$0.isDisabled }.count }
    var orphanCount: Int { items.filter(\.isOrphan).count }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        cancelToken.reset()
        lastError = nil
        statusText = "Đang đọc danh sách…"
        let token = cancelToken
        let throttle = self.throttle

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = StartupScanner().scan(cancel: token) { p in
                throttle.emit {
                    guard let self else { return }
                    self.statusText = p.message
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(Motion.standard) {
                    self.items = result
                    self.isLoading = false
                    self.statusText = "\(result.count) mục"
                }
            }
        }
    }

    /// Bật/tắt một mục. Chạy nền vì với dịch vụ nền thì macOS còn hiện hộp hỏi mật khẩu.
    func toggle(_ item: StartupScanner.Item) {
        guard !item.isApple, !working.contains(item.id) else { return }
        let turnOn = item.isDisabled
        working.insert(item.id)
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure: String?
            do {
                try LaunchControl.setEnabled(turnOn, label: item.label,
                                             plist: item.plist, domain: item.domain)
            } catch {
                failure = LaunchControl.isCancellation(error) ? nil : error.localizedDescription
            }
            // Hỏi lại chính hệ thống thay vì tin vào lệnh vừa chạy: người dùng có thể đã
            // bấm Huỷ ở hộp mật khẩu, và lúc đó không có gì thay đổi cả.
            let disabled = LaunchControl.disabledLabels(in: item.domain)
            let loaded = LaunchControl.loaded()

            DispatchQueue.main.async {
                guard let self else { return }
                self.working.remove(item.id)
                self.lastError = failure
                guard let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                withAnimation(Motion.snappy) {
                    self.items[i].isDisabled = disabled.contains(item.label)
                    self.items[i].isRunning = loaded[item.label].map { $0 != nil } ?? false
                }
            }
        }
    }

    /// Xoá hẳn tệp plist. Đi qua đúng đường dẫn xoá của app: hàng rào an toàn, Thùng rác,
    /// và hộp mật khẩu cho phần nằm ngoài thư mục nhà.
    func remove(_ item: StartupScanner.Item) {
        guard !item.isApple, !working.contains(item.id) else { return }
        working.insert(item.id)
        lastError = nil

        let cleanItem = CleanItem(url: item.plist,
                                  name: item.name,
                                  detail: FileUtils.prettyPath(item.plist),
                                  size: max(1, FileUtils.size(of: item.plist)),
                                  isSelected: true,
                                  requiresAdmin: PrivilegedRunner.needsAdmin(for: item.plist),
                                  isDirectory: false,
                                  emptyContentsOnly: false,
                                  category: "",
                                  safety: .review)
        let request = Remover.Request(
            items: [cleanItem],
            moveToTrash: settings.moveToTrash,
            adminPrompt: "xCleaner cần quyền quản trị để xoá mục khởi động “\(item.name)”.",
            cancel: CancelToken())

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var removed = false
            var failure: String?

            if item.domain.needsAdmin {
                // Dịch vụ nền: tắt và xoá đều cần root, gói chung một lần hỏi mật khẩu.
                do {
                    removed = try LaunchControl.disableAndRemove(label: item.label,
                                                                 plist: item.plist,
                                                                 domain: item.domain)
                    if !removed { failure = "Không xoá được tệp này." }
                } catch {
                    failure = LaunchControl.isCancellation(error) ? nil : error.localizedDescription
                }
            } else {
                // Tắt trước rồi mới xoá: xoá tệp không gỡ được thứ đang nằm sẵn trong bộ nhớ.
                try? LaunchControl.setEnabled(false, label: item.label,
                                              plist: item.plist, domain: item.domain)
                let outcome = Remover.perform(request, progress: { _, _ in })
                DispatchQueue.main.async { CleanLedger.shared.record(outcome.freedBytes) }
                removed = outcome.removedCount > 0
                if !removed && !outcome.wasCancelled {
                    failure = outcome.failures.first?.reason ?? "Không xoá được tệp này."
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.working.remove(item.id)
                self.lastError = failure
                if removed {
                    withAnimation(Motion.standard) {
                        self.items.removeAll { $0.id == item.id }
                    }
                }
            }
        }
    }

    func revealInFinder(_ item: StartupScanner.Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.plist])
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
        // Bundle sắp rơi vào Thùng rác, và cái tai nghe Thùng rác sẽ thấy nó. Đánh dấu trước để
        // người dùng không bị chính xCleaner hỏi "có dọn tàn dư không" ngay sau khi vừa gỡ xong.
        SmartDeleteMemory.shared.suppress(bundleID: app.id)

        let request = Remover.Request(
            items: items,
            moveToTrash: settings.moveToTrash,
            adminPrompt: "xCleaner cần quyền quản trị để gỡ \(app.name) khỏi thư mục hệ thống.")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Remover.perform(request) { _, _ in }
            DispatchQueue.main.async {
                guard let self else { return }
                CleanLedger.shared.record(result.freedBytes)
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.isRemoving = false
                    self.leftovers.removeAll { FileUtils.isGone($0.url) }
                    if FileUtils.isGone(app.url) {
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
    /// Đã quét xong ít nhất một lần. Không có cờ này thì lần quét không ra kết quả nào trông
    /// y hệt lúc chưa bấm gì, và người dùng tưởng cái nút hỏng.
    @Published var hasScanned = false

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
                    self.hasScanned = true
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
            hasScanned = false
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
                CleanLedger.shared.record(result.freedBytes)
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.files.removeAll { FileUtils.isGone($0.url) }
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
    /// Xem chú thích ở `LargeOldStore.hasScanned`.
    @Published var hasScanned = false

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
                    self.hasScanned = true
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
            hasScanned = false
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
                CleanLedger.shared.record(result.freedBytes)
                withAnimation(Motion.standard) {
                    self.outcome = result
                    self.selected = []
                    for i in self.sets.indices {
                        self.sets[i].files.removeAll { FileUtils.isGone($0) }
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
    /// Bấm "Kiểm tra cập nhật…" ở menu: mở trang Cài đặt rồi mới kiểm, vì đó là nơi bày kết quả.
    @Published var requestUpdateCheck = false

    /// App đã được cấp Toàn quyền truy cập đĩa chưa.
    ///
    /// Hỏi lại mỗi lần app được đưa lên trước: người dùng đi sang Cài đặt hệ thống cấp quyền rồi
    /// quay về, và phép thử là một cú đọc thật (`~/.Trash`) chứ không phải cờ nhớ sẵn, nên nó lật
    /// ngay khi macOS bắt đầu cho đọc. Đọc luôn một lần lúc dựng để không bị "nháy": khởi tạo
    /// bằng `true` rồi mới hạ xuống thì cái chấm đỏ nhảy ra sau khi cửa sổ đã hiện.
    @Published private(set) var hasFullDiskAccess = AppState.probeFullDiskAccess()

    let settings = AppSettings()

    private var becameActive: NSObjectProtocol?

    init() {
        becameActive = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFullDiskAccess() }
        }
    }

    deinit {
        if let becameActive { NotificationCenter.default.removeObserver(becameActive) }
    }

    func refreshFullDiskAccess() {
        let now = AppState.probeFullDiskAccess()
        if now != hasFullDiskAccess { hasFullDiskAccess = now }
    }

    private static func probeFullDiskAccess() -> Bool {
        #if DEBUG
        // Để chụp được cả hai trạng thái mà không phải đi cấp/thu quyền thật.
        if let fake = ProcessInfo.processInfo.environment["XCLEANER_FAKE_FDA"] { return fake == "1" }
        #endif
        return FileUtils.hasFullDiskAccess
    }

    private var scanStores: [CleanModule: ScanStore] = [:]
    lazy var uninstall = UninstallStore(settings: settings)
    lazy var startup = StartupStore(settings: settings)
    lazy var largeOld = LargeOldStore(settings: settings)
    lazy var duplicates = DuplicateStore(settings: settings)

    func scanStore(for module: CleanModule) -> ScanStore {
        if let s = scanStores[module] { return s }
        let s = ScanStore(module: module, settings: settings)
        scanStores[module] = s
        return s
    }
}
