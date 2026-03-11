import Flutter
import UIKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let runcore = RuncoreEngine()
    private var pendingPickImageResult: FlutterResult?

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
                case "getMeContactName":
                    result(self.runcore.meContactName())
                case "getInterfaceStats":
                    result(self.runcore.interfaceStatsJSON())
                case "getAnnounces":
                    result(self.runcore.announcesJSON())
                case "setDisplayName":
                    guard let name = call.arguments as? String else {
                        result(FlutterError(code: "bad_args", message: "setDisplayName expects String", details: nil))
                        return
                    }
                    self.runcore.setDisplayName(name)
                    result(nil)
                case "pickImagePath":
                    self.pickImagePath(result: result)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    private func pickImagePath(result: @escaping FlutterResult) {
        if pendingPickImageResult != nil {
            result(FlutterError(code: "busy", message: "picker already active", details: nil))
            return
        }
        guard let root = self.window?.rootViewController else {
            result(FlutterError(code: "no_root_vc", message: "missing root view controller", details: nil))
            return
        }
        pendingPickImageResult = result

        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        root.present(picker, animated: true)
    }
}

extension AppDelegate: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        pendingPickImageResult?(nil)
        pendingPickImageResult = nil
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        defer {
            pendingPickImageResult = nil
        }

        guard let url = info[.imageURL] as? URL else {
            pendingPickImageResult?(FlutterError(code: "no_url", message: "no imageURL", details: nil))
            return
        }
        pendingPickImageResult?(url.path)
    }
}
