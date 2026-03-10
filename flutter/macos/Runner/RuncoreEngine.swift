import Cocoa
import Foundation

final class RuncoreEngine {
    static let shared = RuncoreEngine()

    private var handle: runcore_handle_t = 0
    private var cachedDestinationHashHex: String = ""

    var onLogLine: ((_ level: Int32, _ line: String) -> Void)?
    var logLevel: Int32 = 3

    private(set) var contactsDirPath: String?
    private(set) var sendDirPath: String?
    private(set) var messagesDirPath: String?
    private(set) var configDirPath: String?

    func start() {
        guard handle == 0 else { return }
        cachedDestinationHashHex = ""

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
        sendDirPath = sendDir
        messagesDirPath = messagesDir
        configDirPath = nil

        contactsDir.withCString { cContacts in
            sendDir.withCString { cSend in
                messagesDir.withCString { cMessages in
                    handle = runcore_start(cContacts, cSend, cMessages, logLevel)
                }
            }
        }
        guard handle != 0 else { return }

        if let ptr = runcore_config_dir(handle) {
            configDirPath = String(cString: ptr)
            runcore_free_string(ptr)
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

    func setDisplayName(_ name: String) -> Int32 {
        guard handle != 0 else { return 1 }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rc = trimmed.withCString { cName in
            runcore_set_display_name(handle, cName)
        }
        if rc == 0 {
            cachedDestinationHashHex = ""
        }
        return rc
    }

    func resetProfile() -> Int32 {
        let fm = FileManager.default
        guard let meDir = meContactDirPath(), !meDir.isEmpty else { return 0 }
        let lxmfPath = (meDir as NSString).appendingPathComponent("lxmf")
        if fm.fileExists(atPath: lxmfPath) {
            do {
                try fm.removeItem(atPath: lxmfPath)
            } catch {
                return 2
            }
        }
        return 0
    }

    func destinationHashHex() -> String {
        if !cachedDestinationHashHex.isEmpty {
            return cachedDestinationHashHex
        }
        guard handle != 0 else { return "" }
        guard let ptr = runcore_destination_hash_hex(handle) else { return "" }
        defer { runcore_free_string(ptr) }
        let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cachedDestinationHashHex = value
        return value
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

    func meContactName() -> String {
        guard let contactsDirPath, !contactsDirPath.isEmpty else { return "" }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: contactsDirPath) else { return "" }

        let ownDestination = destinationHashHex()
        if !ownDestination.isEmpty {
            for name in entries.sorted() {
                let dirPath = (contactsDirPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let lxmfPath = (dirPath as NSString).appendingPathComponent("lxmf")
                guard let raw = try? String(contentsOfFile: lxmfPath, encoding: .utf8) else { continue }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if value == ownDestination {
                    return name
                }
            }
        }

        return meContactNameByXattr(in: contactsDirPath, entries: entries)
    }

    private func meContactDirPath() -> String? {
        guard let contactsDirPath, !contactsDirPath.isEmpty else { return nil }
        let name = meContactName()
        guard !name.isEmpty else { return nil }
        return (contactsDirPath as NSString).appendingPathComponent(name)
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
        return systemConfigDir()
    }

    private func meContactNameByXattr(in contactsDir: String, entries: [String]) -> String {
        let fm = FileManager.default
        let key = "user.me"
        for name in entries.sorted() {
            let path = (contactsDir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let has = path.withCString { cPath in
                key.withCString { cKey in
                    getxattr(cPath, cKey, nil, 0, 0, 0) >= 0
                }
            }
            if has {
                return name
            }
        }
        return ""
    }
}
