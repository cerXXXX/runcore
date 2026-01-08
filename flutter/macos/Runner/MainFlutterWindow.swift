import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
