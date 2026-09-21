# Dọn tàn dư khi người dùng tự xoá ứng dụng ("SmartDelete")

Ngày 21/09/2026.

## Mục tiêu

Người dùng bấm ⌘⌫ (hoặc kéo) một ứng dụng vào Thùng rác bằng Finder. Không cần mở xCleaner,
không cần vào mục "Gỡ ứng dụng": một cửa sổ nhỏ nổi lên, liệt kê những tệp app đó để lại trong
máy, cho bỏ chọn từng mục, bấm một nút là sạch.

Đây là thứ AppCleaner gọi là SmartDelete. Khác một điểm đã chốt với người dùng: **cửa sổ phải
mang đúng ngôn ngữ giao diện của xCleaner** (nền kính, bo góc, nút của app), không phải hộp thoại
hệ thống màu trắng.

Ba quyết định của người dùng, không bàn lại:

1. Chạy nền **hoàn toàn vô hình**: không icon Dock, không icon thanh menu.
2. Cửa sổ nổi nhỏ **hiện ngay**, không qua thông báo hệ thống.
3. **Mặc định bật.**

## Vì sao làm được tuy app ký ad-hoc

Chức năng này không cần entitlement nào, cũng không cần Developer ID. Hai thứ nó cần thì xCleaner
đã có: quyền Toàn quyền truy cập đĩa (để đọc `~/.Trash`) và bộ quét tàn dư (`UninstallScanner`).

Điểm cần giữ: **chỉ một binary duy nhất**. macOS nhớ quyền TCC theo designated requirement của
chữ ký, nên một helper riêng sẽ là "app khác" và phải cấp Toàn quyền truy cập đĩa lần thứ hai.
Dùng lại chính binary xCleaner ở một chế độ chạy khác thì quyền đã cấp dùng được ngay.

Vì lý do ấy, **không dùng `SMAppService`** (đòi ký tử tế, xem ghi chú sẵn trong
`PrivilegedRunner.swift`) mà ghi thẳng một LaunchAgent vào `~/Library/LaunchAgents`.

## Kiến trúc

Sáu phần mới, mỗi phần một việc:

| Thành phần | Tệp | Việc |
|---|---|---|
| `TrashWatcher` | `Core/TrashWatcher.swift` | Nghe `~/.Trash`, nói "có `.app` mới rơi vào" |
| `SmartDeleteMemory` | `Core/SmartDeleteMemory.swift` | Nhớ đường dẫn nào không được hỏi lại |
| `LaunchAgentInstaller` | `Core/LaunchAgentInstaller.swift` | Ghi/gỡ plist khởi động cùng máy |
| `SmartDeleteController` | `App/SmartDeleteController.swift` | Xếp hàng, quét tàn dư, bật cửa sổ |
| `LeftoverPanel` + `LeftoverPanelView` | `Views/LeftoverPanel.swift` | Cửa sổ nổi |
| Công tắc trong Cài đặt | `Views/SettingsView.swift` | Bật/tắt |

Luồng:

```
Finder ⌘⌫  →  ~/.Trash đổi  →  TrashWatcher (gộp 0,5s, so ảnh chụp)
   →  SmartDeleteController: lọc qua SmartDeleteMemory → dựng InstalledApp từ Info.plist
   →  UninstallScanner.leftovers(for:) chạy nền
   →  có mục nào không?  không → im lặng
                          có   → LeftoverPanel hiện ra
   →  người dùng bấm Dọn → Remover.perform → "Đã dọn N" → tự đóng
```

## 1. Hai chế độ chạy của cùng một binary

- **Mở bình thường**: `.regular`, icon Dock, cửa sổ chính như hiện nay.
- **Nền**: `.accessory` — không icon Dock, không icon thanh menu, chỉ còn cái tai nghe Thùng rác.

Chuyển giữa hai chế độ:

- Đóng cửa sổ chính mà công tắc đang bật → **app không thoát**
  (`applicationShouldTerminateAfterLastWindowClosed` trả về `false` khi bật), hạ xuống `.accessory`.
- Bấm vào xCleaner trong Finder/Dock lúc đang chạy nền → `applicationShouldHandleReopen` mở lại
  cửa sổ, nâng lên `.regular`, trả `true`. **Đây là cái bẫy đã trả giá ở xDM**: trả `false` hoặc
  quên mở cửa sổ thì người dùng bấm icon mà không có gì xảy ra, đọc ra thành "app hỏng".
- ⌘Q vẫn thoát hẳn, kể cả phần nền. Lần đăng nhập sau LaunchAgent bật lại.

Chạy nền lúc đăng nhập: LaunchAgent gọi `xCleaner --watch`. Ở chế độ này **không được mở cửa sổ**,
mà scene `Window` của SwiftUI thì mặc định tự mở lúc khởi động. Hai lớp chặn:

1. `.defaultLaunchBehavior(.suppressed)` — nhưng nó chỉ có từ macOS 15 còn app đặt đích **macOS
   14**, nên phải bọc trong một `@SceneBuilder` có `if #available(macOS 15, *)`.
2. Trên macOS 14 (và phòng xa cho cả 15+): ở chế độ `--watch`, nghe
   `NSWindow.didBecomeVisibleNotification` và đóng ngay cửa sổ `main` nếu nó kịp hiện.

Chỉ cho phép một tiến trình: nếu đã có tiến trình khác cùng bundle id đang chạy thì kích hoạt nó
rồi tự thoát.

## 2. LaunchAgent

`~/Library/LaunchAgents/com.pikalong.xCleaner.watcher.plist`:

```xml
Label              com.pikalong.xCleaner.watcher
ProgramArguments   [<đường dẫn thật tới xCleaner.app/Contents/MacOS/xCleaner>, --watch]
RunAtLoad          true
ProcessType        Background
```

- **Không khai `KeepAlive`.** Ở Clawdmeter, `KeepAlive/SuccessfulExit=false` cho ra kiểu daemon
  chết im lặng rồi không ai biết. Ở đây người dùng thoát app là cố ý, đừng dựng dậy.
- launchd tự nạp mọi agent trong `~/Library/LaunchAgents` khi đăng nhập, nên **không cần gọi
  `launchctl` lúc bật** — tiến trình hiện tại đã đang trực rồi. Lúc tắt thì gỡ tệp và gọi
  `launchctl bootout gui/<uid>/com.pikalong.xCleaner.watcher`, bỏ qua lỗi (chưa nạp thì bootout
  báo lỗi, đó là bình thường).
- **Mỗi lần khởi động phải đối chiếu đường dẫn trong plist với đường dẫn thật của binary đang
  chạy**, khác thì ghi đè. Người dùng cập nhật app hoặc chuyển thư mục là plist trỏ vào chỗ cũ, và
  một agent trỏ vào chỗ trống thì im lặng không chạy — đúng kiểu hỏng mà không ai phát hiện ra.

## 3. `TrashWatcher`

`FSEventStream` trên `~/.Trash`, gộp sự kiện **0,5 giây** (`latency`), mỗi lần bắn thì chụp lại
danh sách **mục cấp 1** của Thùng rác và so với ảnh chụp trước:

```swift
static func newAppBundles(before: Set<String>, after: [Entry]) -> [URL]
```

Hàm thuần, tách riêng để kiểm thử được: nhận ảnh chụp cũ + danh sách mới, trả về các `.app` vừa
xuất hiện. Quy tắc:

- Chỉ xét **mục cấp 1**: `.app` nằm trong một thư mục cũng vừa bị xoá thì không tính (người dùng
  xoá cả thư mục, không phải gỡ app đó).
- Đuôi phải là `.app` và phải đọc được `CFBundleIdentifier` trong `Contents/Info.plist`. Không có
  bundle id thì không quét được tàn dư, bỏ qua.
- Mục đã có trong ảnh chụp trước thì không tính, kể cả khi ngày sửa đổi thay đổi.

Cần quyền Toàn quyền truy cập đĩa mới đọc được `~/.Trash`. Chưa cấp thì watcher vẫn chạy nhưng
không thấy gì — đúng trạng thái mà chấm than đỏ ở Cài đặt đã nhắc, không thêm hộp thoại mới.

## 4. `SmartDeleteMemory` — không hỏi lại

Một danh sách đường dẫn kèm mốc thời gian trong `UserDefaults`, sống 24 giờ:

- Ghi vào khi **chính xCleaner** gỡ một app (mục "Gỡ ứng dụng" đẩy bundle vào Thùng rác): không
  thì vừa gỡ xong lại bị chính mình hỏi "có dọn tàn dư không".
- Ghi vào khi người dùng **đóng cửa sổ nổi** cho app đó: đã trả lời một lần rồi.
- Bỏ qua luôn chính `xCleaner.app` — người dùng xoá chính app này thì không có gì để mời chào.

## 5. `SmartDeleteController`

- Hàng đợi: nhiều app vào Thùng rác một lúc thì hỏi **lần lượt**, mỗi lúc một cửa sổ.
- Dựng `UninstallScanner.InstalledApp` từ `Info.plist` của bundle đang nằm trong Thùng rác
  (bundle id, tên, phiên bản), rồi gọi `UninstallScanner.leftovers(for:)` trên hàng đợi nền với
  `CancelToken` — **không viết lại bộ quét**.
- `leftovers(for:)` trả về cả chính bundle ở phần tử đầu. Bundle giờ nằm trong Thùng rác nên nó
  hiện thành **một dòng mờ, không tick được** ("Đã ở trong Thùng rác"), giống AppCleaner.
- Quét xong mà bundle không còn trong Thùng rác nữa (người dùng bấm "Put Back", hoặc đã đổ Thùng
  rác) → huỷ, không hiện gì.
- Không tìm được mục nào ngoài chính bundle → **im lặng**. Không có cửa sổ "không tìm thấy gì":
  người dùng không yêu cầu gì cả, đừng làm phiền để khoe.

## 6. Cửa sổ nổi

`NSPanel` chứa một view SwiftUI, dựng bằng đúng bộ phận có sẵn của app: `.glass()`, `Palette`,
`ActionButton`, `Fmt.size`.

- Nền trong suốt + tự vẽ bo góc; **`hasShadow = false`** và tự vẽ bóng trong SwiftUI. macOS vẽ
  bóng theo khung chữ nhật của cửa sổ chứ không theo hình dạng nội dung — bài học từ cửa sổ chính.
- `level = .floating`, `collectionBehavior` có `.canJoinAllSpaces`, `hidesOnDeactivate = false`.
- App đang ở `.accessory` vẫn `NSApp.activate(ignoringOtherApps: true)` được mà **không** sinh ra
  icon Dock — đó là lý do chọn accessory thay vì ẩn kiểu khác.
- Nội dung: dòng đầu "Tìm thấy N tệp còn sót của <Tên app>" + tổng dung lượng; danh sách có
  checkbox, tên, đường dẫn rút gọn, dung lượng, nút hiện trong Finder; đáy là **Đóng** và **Dọn**
  bằng `ActionButton` (`.prominent`).
- **Không dùng nút tròn.** Nút tròn nửa trong nửa ngoài tấm nền là đặc sản của cửa sổ chính và kéo
  theo cả đống bẫy vẽ (dải trong suốt, khuôn cắt, cổng chuột); cửa sổ nhỏ này là hình chữ nhật bo
  góc bình thường.
- Esc = Đóng. Dọn xong: đổi sang dòng "Đã dọn N", chờ 1,5s rồi tự đóng.
- Đóng xong, nếu không còn cửa sổ chính nào mở thì app ở nguyên `.accessory`, không quay lại Dock.

Xoá thì dùng `Remover.perform` như mọi chỗ khác: tôn trọng cài đặt "Chuyển vào Thùng rác", mục
trong `/Library` hỏi mật khẩu qua `PrivilegedRunner`, và cộng vào `CleanLedger`.

## 7. Cài đặt

Thêm `@AppStorage("smartDelete") var smartDelete = true` và một `SettingToggle` trong tab Chung:

> **Dọn tàn dư khi tôi xoá ứng dụng**
> Khi bạn kéo một ứng dụng vào Thùng rác, xCleaner hiện danh sách tệp app đó để lại để bạn dọn
> luôn. Để làm được việc này, xCleaner ở lại chạy nền sau khi bạn đóng cửa sổ (không icon Dock).

Bật → ghi plist, dựng watcher. Tắt → gỡ plist, `bootout`, dừng watcher, app quay lại thoát khi
đóng cửa sổ như cũ.

## Kiểm thử

**Trong `SelfTest` (hàm thuần, chạy được không cần giao diện):**

- `newAppBundles`: thấy app mới; bỏ qua app đã có trong ảnh chụp; bỏ qua `.app` nằm sâu trong thư
  mục; bỏ qua thư mục không phải `.app`; bỏ qua bundle không có `CFBundleIdentifier`.
- `SmartDeleteMemory`: ghi rồi thì bỏ qua; quá 24 giờ thì hỏi lại; chính `xCleaner.app` luôn bị bỏ.
- `LaunchAgentInstaller`: nội dung plist đúng khoá; phát hiện được plist trỏ sai đường dẫn; gỡ thì
  xoá tệp.
- Dựng `InstalledApp` từ một bundle giả: lấy đúng bundle id, tên, phiên bản.

**Bằng tay (ghi vào phần cuối kế hoạch):** dựng một `.app` giả + vài tệp tàn dư giả mang đúng
bundle id, ⌘⌫ nó, xem cửa sổ có hiện đúng không; bấm Dọn và kiểm lại; thử Put Back; thử tắt công
tắc rồi đóng cửa sổ xem app có thoát hẳn không.

## Ngoài phạm vi bản này

- Thùng rác trên ổ ngoài (`/Volumes/*/.Trashes/<uid>`).
- Thông báo hệ thống thay cho cửa sổ nổi.
- Gộp nhiều app vào chung một cửa sổ.
- Hoàn tác sau khi đã dọn (mục vào Thùng rác thì người dùng tự "Put Back" được).
