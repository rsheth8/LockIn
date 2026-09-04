# Contributing to LockIn

## Prerequisites
- macOS, Xcode, XcodeGen (`brew install xcodegen`)
- Apple Developer Team ID for device builds

## Run
```bash
cd LockIn
cp Sources/Resources/Secrets.example.plist Sources/Resources/Secrets.plist
xcodegen generate
open LockIn.xcodeproj
```

Set `DEVELOPMENT_TEAM` in `project.yml` then regenerate.

## Tests
```bash
cd LockIn && xcodebuild -project LockIn.xcodeproj -scheme LockIn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Secrets.plist is gitignored. Family Controls needs Apple approval on a real device.
