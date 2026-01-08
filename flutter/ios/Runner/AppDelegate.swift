import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let runcore = RuncoreEngine()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        runcore.setLogLevel(3)
        runcore.start()

        if let registrar = registrar(forPlugin: "runcore") {
            let channel = FlutterMethodChannel(name: "runcore", binaryMessenger: registrar.messenger())
            channel.setMethodCallHandler { [weak self] call, result in
                guard let self else { return }
                switch call.method {
                case "getPaths":
                    result([
                        "contactsDir": self.runcore.contactsDirPath ?? "",
                        "sendDir": self.runcore.sendDirPath ?? "",
                        "messagesDir": self.runcore.messagesDirPath ?? "",
                        "configDir": self.runcore.configDirPath ?? "",
                    ])
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
