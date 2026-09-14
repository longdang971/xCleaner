import Foundation

/// Thực hiện việc xoá. Tách hẳn khỏi phần quét để chỉ có đúng một chỗ chạm vào đĩa.
enum Remover {

    struct Request {
        var items: [CleanItem]
        /// Chuyển vào Thùng rác thay vì xoá vĩnh viễn (chỉ áp dụng cho tệp không cần quyền root).
        var moveToTrash: Bool
        /// Câu hiển thị trong hộp thoại xin mật khẩu.
        var adminPrompt: String
        /// Cho phép dừng giữa chừng. Phần đã xoá vẫn là đã xoá.
        var cancel: CancelToken? = nil
    }

    /// - Parameters:
    ///   - progress: gọi trên hàng đợi nền, đã được tiết chế bởi lớp gọi.
    ///   - itemFinished: mỗi mục vừa xử lý xong, để màn hình tick dần từng dòng.
    ///     **Mọi** mục trong yêu cầu đều được báo đúng một lần — kể cả mục bị bỏ qua vì đã biến
    ///     mất hay bị hàng rào an toàn chặn. Thiếu một tiếng báo là màn hình đếm hụt và người
    ///     dùng tưởng app dọn sót.
    static func perform(_ request: Request,
                        progress: @escaping (Double, String) -> Void,
                        itemFinished: @escaping (CleanItem, Bool) -> Void = { _, _ in }) -> CleanOutcome {
        var outcome = CleanOutcome()
        let fm = FileManager.default

        let total = max(1, request.items.count)
        var done = 0
        func step(_ name: String) {
            done += 1
            progress(min(1, Double(done) / Double(total)), name)
        }

        var userItems: [CleanItem] = []
        var adminItems: [CleanItem] = []
        /// Mục nằm bên trong một mục khác cũng sắp bị xoá (hoặc trùng đúng đường dẫn với nó).
        /// Chúng biến mất *nhờ* mục kia, nên phải kiểm tra sau cùng và tuyệt đối không cộng
        /// dung lượng lần nữa — trước đây `~/Library/Caches/Homebrew` nằm cả trong "Bộ nhớ đệm"
        /// lẫn "Công cụ lập trình" được tính hai lần, con số "đã giải phóng" vì thế nói quá.
        var coveredItems: [CleanItem] = []

        // ---- Phân loại ----
        // Tập mọi đường dẫn hợp lệ trong yêu cầu, để biết mục nào có mục cha cũng đang bị xoá.
        var allPaths = Set<String>()
        for item in request.items where SafetyGuard.isValid(item.url) {
            allPaths.insert(SafetyGuard.standardized(item.url).path)
        }

        var claimed = Set<String>()
        for item in request.items {
            let path = SafetyGuard.standardized(item.url).path

            if let reason = SafetyGuard.validate(item.url) {
                if case .notExist = reason {
                    // Mục đã biến mất từ lúc quét thì coi như xong, không báo lỗi.
                    outcome.removedCount += 1
                    step(item.name)
                    itemFinished(item, true)
                } else {
                    outcome.failures.append((item.url, reason.localizedDescription))
                    NSLog("[xCleaner] SafetyGuard chặn: %@ — %@", item.url.path,
                          reason.localizedDescription)
                    step(item.name)
                    itemFinished(item, false)
                }
                continue
            }

            if claimed.contains(path) || hasAncestor(of: path, in: allPaths) {
                coveredItems.append(item)
                continue
            }
            claimed.insert(path)

            if item.requiresAdmin || PrivilegedRunner.needsAdmin(for: item.url) {
                adminItems.append(item)
            } else {
                userItems.append(item)
            }
        }

        // ---- Phần không cần quyền: xoá trực tiếp ----
        for item in userItems {
            if request.cancel?.isCancelled == true {
                outcome.wasCancelled = true
                break
            }
            step(item.name)

            // Thư mục bị macOS chặn đọc thì `children` trả về mảng rỗng: không có gì để xoá,
            // mà cũng không có gì chứng minh bên trong đã sạch. Bản trước coi đó là "đã dọn
            // xong" nên người dùng quét lại vẫn thấy nguyên si. Giao thẳng cho đợt chạy root.
            if item.emptyContentsOnly, FileUtils.directoryState(item.url) == .blocked {
                escalate(item, to: &adminItems)
                continue
            }

            let targets: [URL] = item.emptyContentsOnly ? FileUtils.children(of: item.url) : [item.url]
            var itemFailed = false
            var deniedTarget = false
            var trashed = 0

            for t in targets {
                do {
                    if request.moveToTrash {
                        var resulting: NSURL?
                        try fm.trashItem(at: t, resultingItemURL: &resulting)
                        if resulting != nil { trashed += 1 }
                    } else {
                        try fm.removeItem(at: t)
                    }
                } catch {
                    let ns = error as NSError
                    // Không đủ quyền → chuyển sang đợt chạy bằng root thay vì báo lỗi.
                    if ns.domain == NSCocoaErrorDomain &&
                        (ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError) {
                        deniedTarget = true
                        itemFailed = true
                        break
                    }
                    if fm.fileExists(atPath: t.path) {
                        outcome.failures.append((t, ns.localizedDescription))
                        itemFailed = true
                    }
                }
            }

            if deniedTarget {
                escalate(item, to: &adminItems)
                continue
            }

            // Không ném lỗi vẫn chưa chắc là đã sạch: hỏi lại đĩa. Thư mục đọc không được
            // cũng rơi vào đây và được đẩy sang đợt root chứ không lặng lẽ tính là xong.
            if !itemFailed, !isCleared(item) {
                if FileUtils.directoryState(item.url) == .blocked {
                    escalate(item, to: &adminItems)
                    continue
                }
                outcome.failures.append((item.url, "Vẫn còn nội dung sau khi xoá."))
                itemFailed = true
            }

            if !itemFailed {
                outcome.removedCount += 1
                outcome.freedBytes += item.size
                if trashed > 0 { outcome.trashedCount += 1 }
            }
            itemFinished(item, !itemFailed)
        }

        // ---- Phần cần quyền root: gom một lần hỏi mật khẩu ----
        if !adminItems.isEmpty && !outcome.wasCancelled {
            progress(min(1, Double(done) / Double(total)), "Đang chờ quyền quản trị…")
            outcome.usedAdmin = true

            // Mục bị đẩy sang đây vì thiếu quyền sẽ bị root xoá thẳng, kể cả khi người dùng
            // chọn "chuyển vào Thùng rác": không có cách nào bỏ tệp của root vào Thùng rác
            // của người dùng. Đây cũng là hành vi của bản trước.
            let direct = adminItems.filter { !$0.emptyContentsOnly }.map(\.url)
            let toEmpty = adminItems.filter(\.emptyContentsOnly).map(\.url)

            do {
                // Một lệnh duy nhất cho cả hai loại: hai lệnh là hai lần hộp mật khẩu.
                let report = try PrivilegedRunner.removeAndEmpty(remove: direct,
                                                                emptyContents: toEmpty,
                                                                prompt: request.adminPrompt)
                for line in report.errorLines.prefix(20) {
                    NSLog("[xCleaner] rm(root): %@", line)
                }
                // Xác nhận từng mục thay vì tin vào mã thoát của rm.
                for item in adminItems {
                    step(item.name)
                    let gone: Bool
                    if item.emptyContentsOnly {
                        // Thư mục mình không được phép đọc thì "rỗng" chẳng chứng minh điều gì —
                        // lúc đó dựa vào việc lệnh chạy dưới quyền root có kêu ca gì không.
                        gone = FileUtils.directoryState(item.url) == .blocked
                            ? report.errorLines.isEmpty
                            : isCleared(item)
                    } else {
                        gone = !FileUtils.exists(item.url)
                    }
                    if gone {
                        outcome.removedCount += 1
                        outcome.freedBytes += item.size
                    } else {
                        // Đã chạy bằng root mà vẫn còn thì lần sau cũng vậy: nhớ lại để bộ quét
                        // thôi mời người dùng dọn một thứ không dọn được.
                        UndeletableMemory.shared.record(item.url)
                        outcome.failures.append((item.url, "Không xoá được dù đã có quyền quản trị."))
                    }
                    itemFinished(item, gone)
                }
            } catch PrivilegedRunner.Failure.cancelledByUser {
                outcome.wasCancelled = true
                // Huỷ hộp mật khẩu là cả đợt này không được đụng tới. Phải nói ra từng mục,
                // nếu không màn hình đếm hụt và người dùng chỉ thấy "đã dọn xong" trong khi
                // hàng trăm mục còn nguyên.
                for item in adminItems {
                    step(item.name)
                    outcome.failures.append((item.url, "Cần quyền quản trị — bạn đã huỷ nhập mật khẩu."))
                    itemFinished(item, false)
                }
            } catch {
                for item in adminItems {
                    step(item.name)
                    outcome.failures.append((item.url, error.localizedDescription))
                    itemFinished(item, false)
                }
            }
        } else if !adminItems.isEmpty {
            // Người dùng bấm dừng trước khi tới đợt root.
            for item in adminItems {
                step(item.name)
                itemFinished(item, false)
            }
        }

        // ---- Mục được dọn nhờ mục bao nó ----
        for item in coveredItems {
            step(item.name)
            let gone = isCleared(item)
            if gone {
                // Dung lượng đã được tính ở mục bao nó, cộng lần nữa là nói quá.
                outcome.removedCount += 1
            } else if !outcome.wasCancelled {
                outcome.failures.append((item.url, "Vẫn còn sau khi dọn mục chứa nó."))
            }
            itemFinished(item, gone)
        }

        progress(1.0, "Hoàn tất")
        return outcome
    }

    // MARK: - Phụ trợ

    /// Mục xoá trực tiếp không nổi thì đẩy sang đợt chạy bằng root. Nó chưa được báo là xong
    /// ở đây — đợt sau mới biết kết quả thật, báo sớm là màn hình đếm mục đó hai lần.
    private static func escalate(_ item: CleanItem, to adminItems: inout [CleanItem]) {
        var copy = item
        copy.requiresAdmin = true
        adminItems.append(copy)
    }

    /// Mục này đã thật sự sạch chưa — hỏi đĩa chứ không tin vào việc lệnh xoá im lặng.
    /// Thư mục đọc không được trả về `false`: không đọc được thì không chứng minh được gì.
    static func isCleared(_ item: CleanItem) -> Bool {
        guard item.emptyContentsOnly else { return !FileUtils.exists(item.url) }
        switch FileUtils.directoryState(item.url) {
        case .missing, .empty: return true
        case .hasItems, .blocked: return false
        }
    }

    /// Có mục cha nào của `path` cũng nằm trong danh sách sắp xoá không.
    private static func hasAncestor(of path: String, in set: Set<String>) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1 {
            if set.contains(parent) { return true }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return false
    }

    /// Dọn Thùng rác (mọi ổ đĩa) — dùng API riêng vì Thùng rác ở ổ ngoài nằm ở `/Volumes/X/.Trashes/<uid>`.
    static func emptyTrash(items: [CleanItem]) -> CleanOutcome {
        var outcome = CleanOutcome()
        let fm = FileManager.default
        for item in items {
            do {
                try fm.removeItem(at: item.url)
                outcome.removedCount += 1
                outcome.freedBytes += item.size
            } catch {
                outcome.failures.append((item.url, error.localizedDescription))
            }
        }
        return outcome
    }
}
