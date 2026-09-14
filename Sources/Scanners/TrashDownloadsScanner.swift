import Foundation

/// Thùng rác trên mọi ổ đĩa, tệp tải về đã cũ, đính kèm thư và ảnh đĩa đã lắp xong.
struct TrashDownloadsScanner: ModuleScanner {

    /// Tệp tải về cũ hơn ngần này ngày mới được đề xuất.
    var oldDownloadDays: Int = 60

    var stages: [ScanStage] {
        [.init(id: "trash", title: "Thùng rác", icon: "trash.fill"),
         .init(id: "downloads", title: "Thư mục Tải về", icon: "arrow.down.circle.fill"),
         .init(id: "mail", title: "Đính kèm thư", icon: "paperclip"),
         .init(id: "shots", title: "Ảnh chụp màn hình", icon: "camera.viewfinder")]
    }

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var groups: [CleanGroup] = []
        var found: Int64 = 0
        let stage = StageReporter(total: 4, emit: progress)

        // 1. Thùng rác — của người dùng và trên từng ổ đĩa gắn ngoài.
        stage.begin(0)
        var trash: [CleanItem] = []
        var trashBlocked = false
        var trashDirs: [URL] = [FileUtils.homePath(".Trash")]
        let uid = getuid()
        for vol in FileUtils.mountedVolumes() {
            if vol.path == "/" { continue }
            trashDirs.append(vol.appendingPathComponent(".Trashes/\(uid)"))
        }
        for dir in trashDirs {
            // Chỉ báo "cần quyền" khi chính thư mục đó có mặt mà macOS không cho liệt kê. Ổ ngoài
            // có `.Trashes` không cho đi vào thì chẳng biết thư mục của mình có hay không —
            // báo "cần Toàn quyền truy cập đĩa" ở đó là bảo người dùng làm một việc không sửa được gì.
            if FileUtils.presence(dir) == .present, FileUtils.directoryState(dir) == .blocked {
                trashBlocked = true
            }
            guard FileUtils.isDirectory(dir) else { continue }
            for f in FileUtils.children(of: dir) {
                if cancel.isCancelled { break }
                stage.working(f.lastPathComponent)
                if let i = makeItem(f, detail: Fmt.relativeAge(FileUtils.modificationDate(of: f)),
                                    cancel: cancel) {
                    stage.found(i.name, i.size)
                    trash.append(i)
                }
            }
        }
        trash.sort { $0.size > $1.size }
        found += trash.reduce(0) { $0 + $1.size }
        stage.finish(0, bytes: trash.reduce(0) { $0 + $1.size })
        if !trash.isEmpty || trashBlocked {
            groups.append(CleanGroup(id: "trash", title: "Thùng rác",
                                     subtitle: trashBlocked
                                        ? "macOS đang chặn đọc Thùng rác — cần Toàn quyền truy cập đĩa"
                                        : "Bao gồm cả Thùng rác trên ổ đĩa gắn ngoài",
                                     icon: "trash.fill", safety: .safe, items: trash,
                                     isExpanded: false,
                                     needsFullDiskAccess: trashBlocked))
        }
        if cancel.isCancelled { return groups }

        // 2. Tệp cài đặt trong Downloads (.dmg, .pkg, .zip…) đã tải lâu.
        stage.begin(1)
        let installerExts: Set<String> = ["dmg", "pkg", "mpkg", "iso", "zip", "tar", "gz", "bz2",
                                          "xz", "7z", "rar", "sparseimage", "sparsebundle"]
        var installers: [CleanItem] = []
        var oldFiles: [CleanItem] = []
        let cutoff = Date().addingTimeInterval(-Double(oldDownloadDays) * 86_400)

        for f in FileUtils.children(of: FileUtils.homePath("Downloads")) {
            if cancel.isCancelled { break }
            let name = f.lastPathComponent
            if name.hasPrefix(".") { continue }
            stage.working(name)
            let modified = FileUtils.modificationDate(of: f)
            let ext = f.pathExtension.lowercased()
            if installerExts.contains(ext) {
                if let i = makeItem(f, detail: "Bộ cài · \(Fmt.relativeAge(modified))",
                                    selected: (modified ?? .distantPast) < cutoff, cancel: cancel) {
                    installers.append(i)
                }
            } else if let m = modified, m < cutoff {
                if let i = makeItem(f, detail: "Không đụng tới \(Fmt.relativeAge(m))",
                                    selected: false, cancel: cancel) {
                    oldFiles.append(i)
                }
            }
        }
        installers.sort { $0.size > $1.size }
        oldFiles.sort { $0.size > $1.size }
        found += installers.reduce(0) { $0 + $1.size } + oldFiles.reduce(0) { $0 + $1.size }
        stage.finish(1, bytes: installers.reduce(0) { $0 + $1.size }
                     + oldFiles.reduce(0) { $0 + $1.size })

        if !installers.isEmpty {
            groups.append(CleanGroup(id: "installers", title: "Bộ cài đã dùng xong",
                                     subtitle: "DMG, PKG, ZIP trong thư mục Tải về",
                                     icon: "opticaldiscdrive.fill", safety: .review, items: installers))
        }
        if !oldFiles.isEmpty {
            groups.append(CleanGroup(id: "old-downloads", title: "Tệp tải về đã lâu",
                                     subtitle: "Cũ hơn \(oldDownloadDays) ngày — mặc định không chọn",
                                     icon: "clock.arrow.circlepath", safety: .sensitive, items: oldFiles))
        }
        if cancel.isCancelled { return groups }

        // 3. Đính kèm thư đã tải về máy.
        stage.begin(2)
        var mail: [CleanItem] = []
        let mailRoot = FileUtils.homePath("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        for f in FileUtils.children(of: mailRoot) {
            if let i = makeItem(f, selected: false, cancel: cancel) { mail.append(i) }
        }
        for v in FileUtils.children(of: FileUtils.homePath("Library/Mail"))
        where v.lastPathComponent.hasPrefix("V") {
            if cancel.isCancelled { break }
            let downloads = v.appendingPathComponent("MailData/Mail Downloads")
            if let i = makeItem(downloads, name: "Mail Downloads (\(v.lastPathComponent))",
                                selected: false, cancel: cancel) { mail.append(i) }
        }
        found += mail.reduce(0) { $0 + $1.size }
        stage.finish(2, bytes: mail.reduce(0) { $0 + $1.size })
        if !mail.isEmpty {
            groups.append(CleanGroup(id: "mail-attach", title: "Đính kèm thư",
                                     subtitle: "Bản tải về của tệp đính kèm, vẫn còn trên máy chủ",
                                     icon: "paperclip", safety: .review, items: mail))
        }

        // 4. Ảnh chụp màn hình trên Desktop (nhiều người để dồn hàng trăm tấm).
        stage.begin(3)
        var shots: [CleanItem] = []
        for f in FileUtils.children(of: FileUtils.homePath("Desktop")) {
            if cancel.isCancelled { break }
            let n = f.lastPathComponent
            let looksLikeShot = n.hasPrefix("Screenshot") || n.hasPrefix("Ảnh chụp Màn hình")
                || n.hasPrefix("Screen Shot") || n.hasPrefix("CleanShot")
            guard looksLikeShot else { continue }
            if let i = makeItem(f, detail: Fmt.relativeAge(FileUtils.modificationDate(of: f)),
                                selected: false, cancel: cancel) { shots.append(i) }
        }
        shots.sort { $0.size > $1.size }
        found += shots.reduce(0) { $0 + $1.size }
        stage.finish(3, bytes: shots.reduce(0) { $0 + $1.size })
        if !shots.isEmpty {
            groups.append(CleanGroup(id: "screenshots", title: "Ảnh chụp màn hình trên Desktop",
                                     subtitle: "\(shots.count) tấm — mặc định không chọn",
                                     icon: "camera.viewfinder", safety: .sensitive, items: shots))
        }

        stage.done()
        return groups
    }
}
