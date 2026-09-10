# FinderAppToDeviceInstaller

Install mobile apps directly from Finder using a macOS Quick Action and a native device picker.

Select one `.ipa`, `.apk`, or iOS `.app`, then right-click → **Services → Install on Device**. Depending on macOS settings, the action may also appear under Quick Actions. Choose a destination and click **Install**. Use **Refresh** to rescan devices.

## Supported destinations

| Input | Destinations |
| --- | --- |
| `.apk` | Authorized Android phones and running Android emulators |
| `.ipa` or device-built `.app` | Paired, connected iPhones and iPads |
| Simulator-built `.app` | Available iOS simulators; stopped simulators start when selected |

Existing signing and provisioning are preserved. A device IPA cannot run in an iOS simulator. The picker filters platform and connection state; the device installer performs final OS, CPU, and signature checks and displays errors. Apps are installed without automatically launching them.

APK updates use `adb install -r`, retaining app data when supported. Select one file per invocation; split APK sets are not supported. The action may appear for unrelated file types, but validates the selection before proceeding.

## Requirements

- macOS, Swift compiler (`xcrun swiftc`), and Python 3 for building.
- Full Xcode and the necessary simulator runtimes for iOS installations.
- Android SDK platform-tools for Android installations. Lookup includes Android Studio, Homebrew, Unity Hub, `ANDROID_HOME`, and `ANDROID_SDK_ROOT`.
- A paired/connected iOS device or an Android device with debugging authorized.

If `/Applications/Xcode.app` exists, the helper uses it per process without changing the system developer directory. Otherwise it uses the active developer directory.

## Build and install

For editing in VS Code, install the official Swift extension (`swiftlang.swift-vscode`). The root `compile_flags.txt` lets the extension recognize this script-built project and start SourceKit-LSP for formatting and other language features. Workspace settings enable Swift formatting on save; use Shift+Option+F on macOS to format manually. After adding the project configuration, run **Developer: Reload Window** if formatting is unavailable.

From the project directory:

```sh
./scripts/build.sh
./scripts/install.sh
```

The build creates:

- `build/Install on Device.workflow` — complete Quick Action with embedded native helper.
- `dist/Install on Device.zip` — archive suitable for a GitHub Release.

Installation copies the workflow to `~/Library/Services/`. If hidden, enable **Install on Device** in System Settings → Keyboard → Keyboard Shortcuts → Services. Reopen Finder if the menu has not refreshed.

The build targets the current Mac’s architecture and SDK defaults and uses an ad hoc code signature. It is not a notarized, universal distribution build. Test releases on the macOS versions and architectures you intend to support.

## Test

```sh
./tests/test.sh
```

Tests rebuild the package, check Android discovery parsing and literal command arguments, verify signatures and property lists, and exercise installation/removal in a temporary directory. They do not install an app on a phone or modify your real Services folder. End-to-end device installation still requires manual testing with a suitable build and connected device.

GitHub Actions runs these tests on macOS when a pull request is opened, including draft pull requests. Subsequent pushes do not trigger tests. To run them later, use **Actions → Tests → Run workflow** and select the desired branch. The manual run option becomes available once the workflow is on the default branch.

## Uninstall

```sh
./scripts/uninstall.sh
```

This removes only this project's workflow from `~/Library/Services/`. Xcode and Android SDK installations are left in place.

## Repository layout

```text
Sources/DeviceInstaller.swift   Native picker, discovery, and installation
scripts/build.sh               Compile, sign, validate, and archive
scripts/package.py             Generate app and workflow metadata
scripts/install.sh             Install the built Finder action
scripts/uninstall.sh           Remove the installed Finder action
tests/test.sh                  Build and isolated lifecycle checks
```

Build output, local app samples, logs, and signing material are ignored by Git. Publish the ZIP as a release asset rather than committing binaries. Do not include device logs or private app builds in the repository.

## License

This project is licensed under the [MIT License](LICENSE).
