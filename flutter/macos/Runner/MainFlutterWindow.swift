import Cocoa
import FlutterMacOS
import Darwin

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    NSLog("Runcore macOS bundleIdentifier=%@", Bundle.main.bundleIdentifier ?? "<nil>")
    NSLog("Runcore macOS applicationSupport=%@", (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path) ?? "<nil>")

    let engine = RuncoreEngine.shared
    engine.setLogLevel(3)
    engine.start()

    let channel = FlutterMethodChannel(name: "runcore", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getPaths":
        result([
          "contactsDir": engine.contactsDirPath ?? "",
          "sendDir": engine.sendDirPath ?? "",
          "messagesDir": engine.messagesDirPath ?? "",
          "configDir": engine.configDirPath ?? "",
        ])
      case "getMeContactName":
        result(engine.meContactName())
      case "getInterfaceStats":
        result(engine.interfaceStatsJSON())
      case "getAnnounces":
        result(engine.announcesJSON())
      case "setDisplayName":
        guard let name = call.arguments as? String else {
          result(
            FlutterError(
              code: "bad_args",
              message: "setDisplayName expects String",
              details: nil,
            ),
          )
          return
        }
        let rc = engine.setDisplayName(name)
        if rc == 0 {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "set_display_name_failed",
              message: "runcore_set_display_name rc=\(rc)",
              details: nil,
            ),
          )
        }
      case "pickImagePath":
        Self.pickImagePath(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    // Minimal chrome: hide title text + traffic-light buttons.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    styleMask.insert(.fullSizeContentView)

    // Prevent collapsing the app into an unusable narrow strip.
    contentMinSize = NSSize(width: 320, height: 680)
  }
  private static func pickImagePath(result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async {
        Self.pickImagePath(result: result)
      }
      return
    }

    autoreleasepool {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      // Keep compatibility with macOS 10.15 (allowedContentTypes requires 11.0+).
      panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp", "tiff"]

      // Keep a strong ref until completion (defensive; avoids weird lifecycle issues).
      ActiveOpenPanel.shared.panel = panel

      panel.begin { resp in
        defer { ActiveOpenPanel.shared.panel = nil }
        guard resp == .OK, let url = panel.url else {
          result(nil)
          return
        }
        result(url.path)
      }
    }
  }
}

private final class ActiveOpenPanel {
  static let shared = ActiveOpenPanel()
  var panel: NSOpenPanel?
}
