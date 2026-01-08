# runcore_app (Flutter host)

## macOS run

```bash
cd flutter
flutter pub get
cd macos
pod install
open Runner.xcworkspace
```

If `pod` fails with `Could not find 'ffi'`:

```bash
/opt/homebrew/opt/ruby/bin/gem install ffi --user-install
```

Then run `pod install` again.
