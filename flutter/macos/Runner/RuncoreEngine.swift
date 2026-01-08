import Cocoa
import Foundation

final class RuncoreEngine {
    static let shared = RuncoreEngine()

    private var handle: runcore_handle_t = 0

    var onLogLine: ((_ level: Int32, _ line: String) -> Void)?
    var logLevel: Int32 = 3

    private(set) var contactsDirPath: String?
    private(set) var sendDirPath: String?
    private(set) var messagesDirPath: String?
    private(set) var configDirPath: String?

    func start() {
        guard handle == 0 else { return }

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
}

