import Foundation
import Security
import AppKit

/// Chạy một lệnh shell dưới quyền root bằng Authorization Services.
///
/// So với `osascript … with administrator privileges`, cách này cho hộp thoại mật khẩu đẹp hơn hẳn:
/// nó mang **icon và tên xCleaner** cùng câu giải thích của mình, thay vì hiện "osascript".
/// Đổi lại, `AuthorizationExecuteWithPrivileges` đã bị Apple đánh dấu deprecated từ 10.7 nên
/// hàm được nạp động bằng `dlsym`; thiếu symbol thì `PrivilegedRunner` tự lùi về osascript.
enum AuthorizationRunner {

    enum Failure: LocalizedError {
        case unavailable(String)
        case cancelled
        case denied(OSStatus)
        case executionFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unavailable(let m):   return "Không dùng được Authorization Services: \(m)"
            case .cancelled:            return "Bạn đã huỷ yêu cầu quyền quản trị."
            case .denied(let s):        return "Không được cấp quyền quản trị (mã \(s))."
            case .executionFailed(let s): return "Không chạy được lệnh quản trị (mã \(s))."
            }
        }
    }

    private typealias ExecuteWithPrivileges = @convention(c) (
        AuthorizationRef,
        UnsafePointer<CChar>,
        AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    static var isAvailable: Bool { loadSymbol() != nil }

    private static func loadSymbol() -> ExecuteWithPrivileges? {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "AuthorizationExecuteWithPrivileges") else { return nil }
        return unsafeBitCast(sym, to: ExecuteWithPrivileges.self)
    }

    /// - Returns: toàn bộ những gì lệnh in ra (stdout + stderr đã gộp bởi lớp gọi).
    static func run(command: String, prompt: String) throws -> String {
        guard let execute = loadSymbol() else {
            throw Failure.unavailable("thiếu AuthorizationExecuteWithPrivileges")
        }

        // --- Xin quyền, kèm icon và câu giải thích của app ---
        var authRef: AuthorizationRef?
        let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? ""

        var promptBytes = Array(prompt.utf8)
        var iconBytes = Array(iconPath.utf8)

        let status: OSStatus = promptBytes.withUnsafeMutableBufferPointer { promptBuf in
            iconBytes.withUnsafeMutableBufferPointer { iconBuf in
                var envItems = [
                    AuthorizationItem(name: kAuthorizationEnvironmentPrompt,
                                      valueLength: promptBuf.count,
                                      value: promptBuf.baseAddress, flags: 0)
                ]
                if !iconPath.isEmpty {
                    envItems.append(AuthorizationItem(name: kAuthorizationEnvironmentIcon,
                                                      valueLength: iconBuf.count,
                                                      value: iconBuf.baseAddress, flags: 0))
                }

                return envItems.withUnsafeMutableBufferPointer { envBuf -> OSStatus in
                    var environment = AuthorizationEnvironment(count: UInt32(envBuf.count),
                                                               items: envBuf.baseAddress)
                    return withUnsafeMutablePointer(to: &environment) { envPtr -> OSStatus in
                        kAuthorizationRightExecute.withCString { rightName -> OSStatus in
                            var item = AuthorizationItem(name: rightName, valueLength: 0,
                                                         value: nil, flags: 0)
                            return withUnsafeMutablePointer(to: &item) { itemPtr -> OSStatus in
                                var rights = AuthorizationRights(count: 1, items: itemPtr)
                                return AuthorizationCreate(&rights, envPtr,
                                                           [.interactionAllowed, .preAuthorize,
                                                            .extendRights],
                                                           &authRef)
                            }
                        }
                    }
                }
            }
        }

        switch status {
        case errAuthorizationSuccess: break
        case errAuthorizationCanceled: throw Failure.cancelled
        default: throw Failure.denied(status)
        }
        guard let auth = authRef else { throw Failure.denied(status) }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        // --- Chạy lệnh qua /bin/sh -c ---
        var pipe: UnsafeMutablePointer<FILE>?
        let runStatus: OSStatus = "/bin/sh".withCString { toolPath in
            strdupArgs(["-c", command]) { argv in
                execute(auth, toolPath, [], argv, &pipe)
            }
        }

        switch runStatus {
        case errAuthorizationSuccess: break
        case errAuthorizationCanceled: throw Failure.cancelled
        default: throw Failure.executionFailed(runStatus)
        }

        // Đọc tới hết pipe — đây cũng là cách biết tiến trình con đã kết thúc.
        var output = ""
        if let pipe {
            var buffer = [CChar](repeating: 0, count: 4096)
            while fgets(&buffer, Int32(buffer.count), pipe) != nil {
                output += String(cString: buffer)
            }
            fclose(pipe)
        }
        return output
    }

    /// Dựng mảng `char *argv[]` kết thúc bằng NULL rồi giải phóng sau khi dùng.
    private static func strdupArgs<R>(_ args: [String],
                                      _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        defer { for p in cArgs where p != nil { free(p) } }
        return cArgs.withUnsafeBufferPointer { buf in body(buf.baseAddress!) }
    }
}
