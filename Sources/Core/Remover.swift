import Foundation

/// Thực hiện việc xoá. Tách hẳn khỏi phần quét để chỉ có đúng một chỗ chạm vào đĩa.
enum Remover {

    /// Loại việc đang dọn. Quyết định xem công tắc "Chuyển vào Thùng rác" trong Cài đặt có
    /// tiếng nói hay không — xem `movesToTrash(_:setting:)`.
    enum Kind {
        /// Rác hệ thống, bộ nhớ đệm, bản tải về… — thứ người dùng gọi là "dọn rác".
        case junk
        /// Mục khởi động cùng máy: xoá hẳn tệp plist.
        case startupItem
        /// Tàn dư của một ứng dụng vừa bị gỡ, kể cả chính bundle app.
        case leftovers
        /// Tệp của chính người dùng: bản trùng lặp, tệp to và cũ.
        case personalFile
    }

    /// Công tắc trong Cài đặt chỉ nói về việc **dọn rác**.
    ///
    /// Tàn dư và tệp cá nhân thì luôn vào Thùng rác, không hỏi: người dùng vừa tự tay kéo app
    /// vào Thùng rác nên họ chờ thấy tàn dư nằm cạnh đó, và bấm nhầm thì còn lấy lại được.
    /// Trước đây bảng tàn dư cũng đọc công tắc này, mà công tắc mặc định TẮT — nên nó xoá vĩnh
    /// viễn trong khi người dùng đi mở Thùng rác tìm.
    static func movesToTrash(_ kind: Kind, setting: Bool) -> Bool {
        switch kind {
        case .junk, .startupItem: return setting
        case .leftovers, .personalFile: return true
        }
    }

    struct Request {
        var items: [CleanItem]
        /// Chuyển vào Thùng rác thay vì xoá vĩnh viễn (chỉ áp dụng cho tệp không cần quyền root).
        /// Đừng đọc thẳng công tắc trong Cài đặt — hỏi `movesToTrash(_:setting:)`.
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
        /// Mốc để phân biệt thứ *không xoá nổi* với thứ *vừa được tạo lại*. Lùi vài giây cho
        /// chắc: thà bỏ sót một lần ghi sổ còn hơn ghi oan.
        let startedAt = Date().addingTimeInterval(-2)

        let total = max(1, request.items.count)
        var done = 0
        /// Vòng tiến trình chỉ nhích khi một mục thật sự xong. Mục bị đẩy sang đợt root đi qua
        /// hai vòng lặp, đếm ở cả hai chỗ là tiến trình chạm 100% khi còn nửa việc chưa làm.
        func finish(_ item: CleanItem, _ ok: Bool) {
            done += 1
            progress(min(1, Double(done) / Double(total)), item.name)
            itemFinished(item, ok)
        }
        /// Chỉ đổi dòng chữ "đang xử lý…", không đụng tới con số.
        func announce(_ name: String) {
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
                    finish(item, true)
                } else {
                    outcome.failures.append((item.url, reason.localizedDescription))
                    NSLog("[xCleaner] SafetyGuard chặn: %@ — %@", item.url.path,
                          reason.localizedDescription)
                    finish(item, false)
                }
                continue
            }

            // "Dọn ruột" một liên kết tượng trưng: không bên nào dọn được gì (liệt kê bằng URL
            // và `find` đều không đi theo liên kết — đã đo), nhưng các phép kiểm tra lại nhìn nó
            // theo những cách khác nhau, và `find` thì thấy "rỗng" nên từng khẳng định là đã dọn.
            // Bộ quét vốn bỏ qua liên kết (dung lượng 0), nên gặp ở đây tức là nó bị thay giữa
            // lúc quét và lúc dọn: không đụng, không báo xong.
            if item.emptyContentsOnly, isSymlink(item.url) {
                outcome.failures.append((item.url, "Đã bị thay bằng liên kết tượng trưng."))
                finish(item, false)
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
            announce(item.name)

            // Thư mục bị macOS chặn đọc thì `children` trả về mảng rỗng: không có gì để xoá,
            // mà cũng không có gì chứng minh bên trong đã sạch. Bản trước coi đó là "đã dọn
            // xong" nên người dùng quét lại vẫn thấy nguyên si. Giao thẳng cho đợt chạy root.
            if item.emptyContentsOnly, FileUtils.directoryState(item.url) == .blocked {
                escalate(item, to: &adminItems)
                continue
            }

            let targets: [URL] = item.emptyContentsOnly ? FileUtils.children(of: item.url) : [item.url]
            // Thư mục đệm tự rỗng từ lúc quét tới giờ (app tự dọn) thì mục vẫn tính là xong,
            // nhưng không được khoe dung lượng đo lúc quét như thể chính mình vừa giải phóng.
            let nothingToFree = item.emptyContentsOnly && targets.isEmpty
            var itemFailed = false
            var deniedTarget = false
            var trashed = 0

            for t in targets {
                do {
                    // Thứ vốn đã nằm trong Thùng rác thì không chuyển vào Thùng rác được nữa:
                    // macOS nhận lệnh, trả về "thành công", trả lại đúng đường dẫn cũ và để
                    // nguyên tệp ở đó (đã đo trên máy). Những mục này luôn xoá thẳng.
                    if request.moveToTrash && !isInsideTrash(t) {
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
                    // Chỉ bỏ qua lỗi khi chắc chắn thứ đó đã không còn. `fileExists` báo `false`
                    // cả khi chỉ là không được nhìn — tin nó là nuốt mất một lần xoá hỏng.
                    if !FileUtils.isGone(t) {
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
                if !nothingToFree { outcome.freedBytes += item.size }
                if trashed > 0 { outcome.trashedCount += 1 }
            }
            finish(item, !itemFailed)
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
                // Xác nhận từng mục bằng lời khẳng định của chính root cho đúng đường dẫn đó —
                // không phải mã thoát của rm, không phải "không thấy báo lỗi". Không có tin tức
                // gì về một mục thì mục đó là CHƯA xoá.
                for item in adminItems {
                    let path = SafetyGuard.standardized(item.url).path
                    // Root bảo sạch thì vẫn phải hợp với thứ app tự nhìn thấy — trừ khi app
                    // không được phép nhìn, lúc đó lời của root là tất cả những gì ta có.
                    let appAgrees = FileUtils.directoryState(item.url) == .blocked || isCleared(item)
                    let gone = report.confirmedGone.contains(path) && appAgrees
                    if gone {
                        outcome.removedCount += 1
                        outcome.freedBytes += item.size
                    } else {
                        if report.confirmedLeft.contains(path),
                           hasOldContent(item, before: startedAt) {
                            // Root khẳng định vẫn còn, VÀ thứ còn lại là thứ cũ chứ không phải thứ
                            // hệ thống vừa tạo lại: lần sau cũng không xoá nổi, nhớ lại để bộ quét
                            // thôi mời người dùng dọn nó.
                            UndeletableMemory.shared.record(item.url)
                        }
                        outcome.failures.append((item.url, "Không xoá được dù đã có quyền quản trị."))
                    }
                    finish(item, gone)
                }
            } catch PrivilegedRunner.Failure.cancelledByUser {
                outcome.wasCancelled = true
                // Huỷ hộp mật khẩu là cả đợt này không được đụng tới. Phải nói ra từng mục,
                // nếu không màn hình đếm hụt và người dùng chỉ thấy "đã dọn xong" trong khi
                // hàng trăm mục còn nguyên.
                for item in adminItems {
                    outcome.failures.append((item.url, "Cần quyền quản trị — bạn đã huỷ nhập mật khẩu."))
                    finish(item, false)
                }
            } catch {
                for item in adminItems {
                    outcome.failures.append((item.url, error.localizedDescription))
                    finish(item, false)
                }
            }
        } else if !adminItems.isEmpty {
            // Người dùng bấm dừng trước khi tới đợt root.
            for item in adminItems { finish(item, false) }
        }

        // ---- Mục được dọn nhờ mục bao nó ----
        for item in coveredItems {
            let gone = isCleared(item)
            if gone {
                // Dung lượng đã được tính ở mục bao nó, cộng lần nữa là nói quá.
                outcome.removedCount += 1
            } else if !outcome.wasCancelled {
                outcome.failures.append((item.url, "Vẫn còn sau khi dọn mục chứa nó."))
            }
            finish(item, gone)
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
        guard item.emptyContentsOnly else { return FileUtils.isGone(item.url) }
        switch FileUtils.directoryState(item.url) {
        case .missing, .empty: return true
        case .hasItems, .blocked: return false
        }
    }

    /// Thứ còn lại sau khi root xoá có phải là thứ đã có từ trước không.
    ///
    /// Thư mục đệm của một dịch vụ đang chạy bị xoá xong là được tạo lại ngay trong tích tắc.
    /// Nó "vẫn còn", nhưng lần nào cũng dọn được — ghi sổ "không xoá được" là giấu vĩnh viễn
    /// một chỗ rác sẽ lại phình to. Chỉ ghi sổ khi thấy được tận mắt nội dung CŨ còn nằm đó;
    /// không nhìn được thì không biết, và không biết thì không ghi.
    static func hasOldContent(_ item: CleanItem, before cutoff: Date) -> Bool {
        func isOld(_ url: URL) -> Bool {
            guard let d = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                return false
            }
            return d < cutoff
        }
        if item.emptyContentsOnly {
            guard FileUtils.directoryState(item.url) != .blocked else { return false }
            return FileUtils.children(of: item.url).contains(where: isOld)
        }
        guard FileUtils.presence(item.url) == .present else { return false }
        return isOld(item.url)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    /// Mục này có nằm trong Thùng rác không — của người dùng hay của một ổ đĩa gắn ngoài.
    private static func isInsideTrash(_ url: URL) -> Bool {
        let path = SafetyGuard.standardized(url).path
        if path.hasPrefix(NSHomeDirectory() + "/.Trash/") { return true }
        // Ổ ngoài: /Volumes/<tên ổ>/.Trashes/<uid>/…
        return path.range(of: #"^/Volumes/[^/]+/\.Trashes/"#, options: .regularExpression) != nil
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
}
