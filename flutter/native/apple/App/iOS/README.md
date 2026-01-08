# Runcore

Open `flutter/native/apple/App/iOS/Runcore.xcodeproj` in Xcode and run on a simulator/device.

Build the Go xcframework first:

```bash
../../Frameworks/build.sh ios
```

Then open the Xcode project and run. It links against `flutter/native/apple/Frameworks/iOS/Runcore.xcframework`.
