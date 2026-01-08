import Darwin
import Foundation

final class RuncoreEngine {
    private var handle: runcore_handle_t = 0
    private var cachedDestHex: String = ""
    private var cachedMeFolderName: String = ""

    var onLogLine: ((_ level: Int32, _ line: String) -> Void)?
    var displayName: String = "Me"
    var logLevel: Int32 = 3
    private(set) var contactsDirPath: String?
    private(set) var configDirPath: String?
    private(set) var sendDirPath: String?
    private(set) var messagesDirPath: String?

    var contactsDirectoryURL: URL? {
        guard let path = contactsDirPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var configDirectoryURL: URL? {
        guard let path = configDirPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    struct ContactAvatarInfo {
        let hashHex: String?
    }

    struct ContactInfo {
        let displayName: String?
        let avatar: ContactAvatarInfo?
    }

    func start() {
        guard handle == 0 else { return }

        // Install log hook before starting Reticulum so early init logs are captured.
        runcore_set_log_cb({ userData, level, line in
            guard let userData else { return }
            let engine = Unmanaged<RuncoreEngine>.fromOpaque(userData).takeUnretainedValue()
            let s = line.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async {
                engine.onLogLine?(level, s)
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        let root = iCloudRootDir()
        let contactsDir = (root as NSString).appendingPathComponent("contacts")
        let sendDir = (root as NSString).appendingPathComponent("send")
        let messagesDir = (root as NSString).appendingPathComponent("messages")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: contactsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: sendDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: messagesDir, withIntermediateDirectories: true)
        contactsDirPath = contactsDir
        configDirPath = nil
        sendDirPath = sendDir
        messagesDirPath = messagesDir

        contactsDir.withCString { cContacts in
            sendDir.withCString { cSend in
                messagesDir.withCString { cMessages in
                    handle = runcore_start(cContacts, cSend, cMessages, logLevel)
                }
            }
        }
        guard handle != 0 else { return }
        cachedDestHex = ""

        if let ptr = runcore_config_dir(handle) {
            configDirPath = String(cString: ptr)
            runcore_free_string(ptr)
        }

        cachedMeFolderName = findMeFolderName() ?? ""
        if !cachedMeFolderName.isEmpty {
            displayName = cachedMeFolderName
        }
    }

    func stop() {
        guard handle != 0 else { return }
        _ = runcore_stop(handle)
        handle = 0
    }

    func setLogLevel(_ level: Int32) {
        logLevel = level
        runcore_set_loglevel(level)
    }

    func destinationHashHex() -> String {
        if !cachedDestHex.isEmpty { return cachedDestHex }
        guard handle != 0 else { return cachedDestHex }
        guard let contactsDirPath, !contactsDirPath.isEmpty else { return cachedDestHex }
        let meName = cachedMeFolderName.isEmpty ? (findMeFolderName() ?? displayName) : cachedMeFolderName
        guard !meName.isEmpty else { return cachedDestHex }
        let meDir = (contactsDirPath as NSString).appendingPathComponent(meName)
        let lxmfPath = (meDir as NSString).appendingPathComponent("lxmf")
        if let s = try? String(contentsOfFile: lxmfPath, encoding: .utf8) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !v.isEmpty {
                cachedDestHex = v
                return v
            }
        }
        return cachedDestHex
    }

    private func findMeFolderName() -> String? {
        guard let contactsDirPath, !contactsDirPath.isEmpty else { return nil }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: contactsDirPath) else { return nil }
        for name in entries {
            let p = (contactsDirPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            if hasMeXattr(path: p) {
                return name
            }
        }
        return nil
    }

    private func hasMeXattr(path: String) -> Bool {
        let key = "user.runcore.me"
        return path.withCString { cPath in
            key.withCString { cKey in
                let rc = getxattr(cPath, cKey, nil, 0, 0, 0)
                return rc >= 0
            }
        }
    }

    func interfaceStatsJSON() -> String {
        guard handle != 0 else { return "{}" }
        guard let ptr = runcore_interface_stats_json(handle) else { return "" }
        defer { runcore_free_string(ptr) }
        return String(cString: ptr)
    }

    func announcesJSON() -> String {
        guard let configDirPath, !configDirPath.isEmpty else { return "" }
        let path = (configDirPath as NSString).appendingPathComponent("storage/announces.json")
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func contactInfoFromDisk(destHashHex: String) -> ContactInfo? {
        guard let configDirPath, !configDirPath.isEmpty else { return nil }
        let dest = destHashHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !dest.isEmpty else { return nil }
        let announcesPath = (configDirPath as NSString).appendingPathComponent("storage/announces.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: announcesPath)) else { return nil }
        struct AnnounceEntry: Decodable {
            let destinationHashHex: String
            let displayName: String?
            let avatarHashHex: String?

            enum CodingKeys: String, CodingKey {
                case destinationHashHex = "destination_hash_hex"
                case displayName = "display_name"
                case avatarHashHex = "avatar_hash_hex"
            }
        }
        guard let entries = try? JSONDecoder().decode([AnnounceEntry].self, from: data) else { return nil }
        guard let hit = entries.first(where: { $0.destinationHashHex.lowercased() == dest }) else { return nil }
        let av = (hit.avatarHashHex?.isEmpty == false) ? ContactAvatarInfo(hashHex: hit.avatarHashHex?.lowercased()) : nil
        return ContactInfo(displayName: hit.displayName, avatar: av)
    }

    private func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        if let s {
            return s.withCString { body($0) }
        }
        return body(nil)
    }

    func setInterfaceEnabled(name: String, enabled: Bool) -> Int32 {
        guard handle != 0 else { return 1 }
        return name.withCString { cName in
            runcore_set_interface_enabled(handle, cName, enabled ? 1 : 0)
        }
    }

    func defaultLXMDConfigText() -> String {
        guard let ptr = runcore_default_lxmd_config() else { return "" }
        defer { runcore_free_string(ptr) }
        return String(cString: ptr)
    }

    func defaultRNSConfigText() -> String {
        guard let ptr = runcore_default_rns_config() else { return "" }
        defer { runcore_free_string(ptr) }
        return String(cString: ptr)
    }

    func enqueueSendText(destHashHex: String, title: String, content: String) -> Bool {
        guard let sendDirPath, !sendDirPath.isEmpty else { return false }
        let dest = destHashHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !dest.isEmpty else { return false }
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = safeTitle.isEmpty ? "msg" : safeTitle
        let fileName = "\(prefix) -- \(UUID().uuidString).txt"
        let dir = (sendDirPath as NSString).appendingPathComponent(dest)
        let target = (dir as NSString).appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let data = content.data(using: .utf8) ?? Data()
            try data.write(to: URL(fileURLWithPath: target), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    func enqueueSendFile(destHashHex: String, fileURL: URL, caption: String?) -> Bool {
        guard let sendDirPath, !sendDirPath.isEmpty else { return false }
        let dest = destHashHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !dest.isEmpty else { return false }
        let dir = (sendDirPath as NSString).appendingPathComponent(dest)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let target = URL(fileURLWithPath: dir).appendingPathComponent(fileURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                let alt = URL(fileURLWithPath: dir).appendingPathComponent("\(UUID().uuidString) \(fileURL.lastPathComponent)")
                try FileManager.default.copyItem(at: fileURL, to: alt)
            } else {
                try FileManager.default.copyItem(at: fileURL, to: target)
            }
            if let caption, !caption.isEmpty {
                let capURL = URL(fileURLWithPath: dir).appendingPathComponent("caption.txt")
                let data = caption.data(using: .utf8) ?? Data()
                try data.write(to: capURL, options: [.atomic])
            }
            return true
        } catch {
            return false
        }
    }

    func setAvatarImage(mime: String, data: Data) -> Int32 {
        guard handle != 0 else { return 1 }
        guard let me = cachedMeFolderName.isEmpty ? findMeFolderName() : cachedMeFolderName else { return 2 }
        guard let contactsDirPath else { return 2 }
        let meDir = (contactsDirPath as NSString).appendingPathComponent(me)
        let ext: String
        switch mime.lowercased() {
        case "image/png": ext = "png"
        case "image/jpeg", "image/jpg": ext = "jpg"
        case "image/heic": ext = "heic"
        default: ext = "bin"
        }
        let target = (meDir as NSString).appendingPathComponent("avatar.\(ext)")
        do {
            try data.write(to: URL(fileURLWithPath: target), options: [.atomic])
        } catch {
            return 3
        }
        return 0
    }

    func setAvatarPNG(_ data: Data) -> Int32 {
        guard handle != 0 else { return 1 }
        guard !data.isEmpty else { return 2 }
        return setAvatarImage(mime: "image/png", data: data)
    }

    func clearAvatar() -> Int32 {
        guard handle != 0 else { return 1 }
        guard let me = cachedMeFolderName.isEmpty ? findMeFolderName() : cachedMeFolderName else { return 2 }
        guard let contactsDirPath else { return 2 }
        let meDir = (contactsDirPath as NSString).appendingPathComponent(me)
        let fm = FileManager.default
        for ext in ["png", "jpg", "jpeg", "heic", "bin"] {
            let p = (meDir as NSString).appendingPathComponent("avatar.\(ext)")
            try? fm.removeItem(atPath: p)
        }
        return 0
    }

    func updateDisplayNameAndAnnounce(_ name: String) {
        displayName = name
        guard handle != 0 else { return }
        name.withCString { cName in
            _ = runcore_set_display_name(handle, cName)
        }
    }

    func setDisplayName(_ name: String) {
        displayName = name
        guard handle != 0 else { return }
        name.withCString { cName in
            _ = runcore_set_display_name(handle, cName)
        }
    }

    func restart() {
        guard handle != 0 else { return }
        _ = runcore_restart(handle)
        cachedDestHex = ""
    }

    private func systemConfigDir() -> String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Runcore", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func iCloudRootDir() -> String {
        let fm = FileManager.default
        if let base = fm.url(forUbiquityContainerIdentifier: "iCloud.ru.at.runcore") ?? fm.url(forUbiquityContainerIdentifier: nil) {
            let docs = base.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs.path
        }

        // Fallback (no iCloud): keep everything under Application Support.
        return systemConfigDir()
    }
}
