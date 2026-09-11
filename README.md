# FinderAppToDeviceInstaller

Install mobile apps from Finder using a macOS Quick Action and a native device picker. Select one app file, choose **Services → Install on Device**, then choose its destination. The tool installs the app without automatically launching it.

## Supported inputs and compatibility

| Selected input | Destinations |
| --- | --- |
| `.apk` | Authorized Android phones and saved or running Android emulators |
| Device-built `.app`, directly or inside an `.ipa` | Paired iPhones and iPads over Wi-Fi or USB |
| Simulator-built `.app`, directly or inside an `.ipa` | Available iOS simulators with installed runtimes |

For an iOS `.app`, the helper reads `CFBundleSupportedPlatforms` from its `Info.plist`: `iPhoneOS` selects physical devices, and `iPhoneSimulator` selects simulators. For an `.ipa`, it first extracts exactly one `.app` from `Payload`, then performs the same check. Missing or unrecognized platform metadata is rejected. The filename or `.ipa` extension alone does not determine the destination.

**A listed destination is not a guarantee of compatibility.** The picker uses the declared platform; it does not inspect the executable to verify its architecture or preflight minimum OS versions, signatures, or provisioning. Installation can still fail on an individual destination, and the helper displays the installer’s error.

Device and simulator builds are separate artifacts. A normal iPhone `.ipa` cannot run in Simulator; obtain a simulator build from the app developer or your build pipeline. The helper does not rebuild, convert, re-sign, or repair mobile apps. Existing signing and provisioning are preserved.

- Select one file per invocation. Batch installation and Android split APK sets are not supported.
- `.zip` input is not supported. Extract a simulator app download first, then select its `.app` bundle.
- APK updates use `adb install -r`, retaining app data when supported.
- The Finder action may appear for unrelated file types; the helper validates the selection before proceeding.

## Requirements

Choose the requirements for your destination; a physical device is optional when using a simulator or emulator.

| Use | Requirements |
| --- | --- |
| Run the Finder action | macOS and an installed workflow compatible with your Mac |
| Install on iPhone or iPad | Full Xcode, initial device pairing, Developer Mode, and a compatible signed app |
| Install on iOS Simulator | Full Xcode, the required simulator runtime and a created simulator, plus a simulator-built app |
| Install on Android phone | Android SDK platform-tools (`adb`), USB debugging, and authorization of this Mac on the phone |
| Install on Android emulator | Android SDK platform-tools, Android Emulator, and a saved AVD with its system image |
| Build this tool from source | Swift compiler (`xcrun swiftc`) and Python 3, in addition to macOS |

The generated Finder helper targets the build Mac’s architecture and SDK defaults. It is ad hoc signed, not notarized, and not a universal distribution build. No minimum macOS version or cross-Mac compatibility matrix has been validated. A downloaded workflow may be blocked by macOS security checks; signature verification during the build does not establish Gatekeeper acceptance. Build from source if a suitable packaged build is unavailable.

If `/Applications/Xcode.app` exists, the helper uses its developer directory for commands without changing the system-wide setting. Otherwise it uses the active developer directory. Android tool lookup includes common Android Studio, Homebrew, and Unity Hub locations, plus `ANDROID_HOME` and `ANDROID_SDK_ROOT`. Environment variables configured only in your terminal may not be available to a Finder-launched action.

## Install and update

### From source

Clone or download this repository, open a terminal in its directory, and run:

```sh
./scripts/build.sh
./scripts/install.sh
```

This builds the helper and copies `Install on Device.workflow` to `~/Library/Services/`. Installation is per user and does not require a system-wide installation.

**After updating the source, run both commands again.** The install script builds automatically only when the built helper is missing; it does not check whether an existing build is out of date.

### From a packaged workflow

If you receive a compatible `Install on Device.zip` produced by this project:

1. Extract the ZIP to obtain `Install on Device.workflow`.
2. In Finder, choose **Go → Go to Folder** and enter `~/Library/Services/`. Create the `Services` folder in your user Library if necessary.
3. Copy the workflow there. To update, replace the previous copy of this workflow.
4. Reopen Finder if the action does not appear.

Keep the name `Install on Device.workflow` and that location: the action uses this path to launch its embedded helper. The ZIP contains the workflow, not the repository’s build or install scripts. This procedure does not bypass macOS security checks, and downloading a packaged workflow does not remove its Xcode or Android SDK requirements.

## Use from Finder

1. Select one `.ipa`, `.apk`, or iOS `.app`.
2. Right-click → **Services → Install on Device**. Depending on macOS settings, it may appear under **Quick Actions** instead.
3. Choose a destination and click **Install**. Use **Refresh** to rescan.
4. Wait for startup or connection, then installation. Open the installed app yourself on the destination.

Only the destination family selected by the app’s platform is shown. Physical iPhones and iOS simulators are not combined into one list. Starting a simulator or emulator opens its window; this does not launch the installed mobile app.

### Wireless iPhone connections

Pair the device in Xcode once and enable Developer Mode. For Wi-Fi use, keep the Mac and iPhone on the same network. USB is also supported. Xcode does not need to remain open for the helper to attempt reconnection.

Paired iPhones stay visible when their development connection is inactive. **Not connected** may mean the phone is offline or simply needs a connection; it does not prove installation is impossible. Choose the phone and click **Install**. The helper requests device details and waits up to 45 seconds for an active connection and available developer services. Unlock the phone and keep it nearby.

**Cancel** stops the connection attempt and returns to the picker. Connection failures offer **Retry**, **Refresh**, or **Cancel**. Once installation begins, the connection Cancel button is hidden. Installation is not automatically retried: if it fails or times out, check the app on the device before installing again.

### iOS simulators

Running and stopped simulators with available runtimes are listed, with running simulators first. **Start & install** boots the selected simulator, waits up to three minutes for boot completion, opens Simulator, and installs the app. The simulator remains running afterward.

This startup flow currently has no Cancel button or Retry/Refresh recovery dialog. A failure displays an error and exits the helper; invoke the Finder action again to retry. The explicit boot wait runs only when the simulator was reported as stopped during discovery.

### Android emulators

Create an AVD in Android Studio’s Device Manager and install Android Emulator and its system image through SDK Manager. Android Studio can be closed during installation. The helper finds the emulator tool through `ANDROID_HOME`, `ANDROID_SDK_ROOT`, the default Android Studio SDK, or the SDK containing the discovered `adb`.

The picker lists connected phones, running emulators, then saved AVDs not matched to a running instance:

- **Start & install** launches a saved AVD in its own window.
- **Running / starting** reuses an existing instance and waits for readiness.
- **Status unknown** means an existing emulator has not reported its AVD identity. The helper waits rather than risking a duplicate launch; refresh after it finishes starting.

Startup waits up to three minutes for the selected AVD’s ADB connection, Android boot completion, and package manager. **Cancel** stops waiting and prevents installation, but leaves the emulator open. Startup failures offer **Retry** and **Refresh**. Once installation begins, the Cancel button is hidden. Installation is attempted once, and the emulator remains open afterward.

Missing emulator tools do not prevent installation on connected phones. The helper does not create AVDs, download system images, or wipe emulator data.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Finder action is missing | Confirm the workflow is in `~/Library/Services/`. Check the Services/Quick Actions controls in System Settings and reopen Finder. |
| Downloaded workflow is blocked | The package is not notarized. Confirm its source and compatibility; use the source-build instructions if needed. |
| No iOS simulators appear | Confirm the app declares the simulator platform and that Xcode has the required runtimes and available simulators. A device build deliberately shows physical devices instead. |
| iPhone cannot connect | Unlock it, check initial pairing and Developer Mode, then the Wi-Fi network. Try USB and Refresh. |
| Android phone is missing | Enable USB debugging and accept the authorization prompt on the phone. Confirm Android SDK platform-tools are installed. |
| Saved Android emulator is missing | Check that Android Emulator, an AVD, and its system image are installed in the SDK the helper can find. |
| Emulator startup times out | Open it in Android Studio’s Device Manager to inspect startup problems, then use Retry or Refresh. |
| Destination appears but installation fails | Read the installer error. Check the app’s target platform, architecture, minimum OS, and, for physical iOS devices, signing and provisioning. Reconnecting cannot repair an incompatible build. |
| Changes to this tool have no effect | Run `./scripts/build.sh` and then `./scripts/install.sh` to replace the installed workflow. |

## Uninstall

From the repository:

```sh
./scripts/uninstall.sh
```

If you installed only a packaged workflow, remove `Install on Device.workflow` from `~/Library/Services/` in Finder instead.

Uninstalling removes the Finder action. It does not remove apps installed on devices, simulator/emulator data, Xcode, or Android SDK installations. It also leaves the repository’s local build output in place.

## Development

### Editing

For VS Code, install the official Swift extension (`swiftlang.swift-vscode`). The root `compile_flags.txt` lets the extension recognize this script-built project and start SourceKit-LSP. Workspace settings enable Swift formatting on save; use Shift+Option+F on macOS to format manually. After adding the configuration, run **Developer: Reload Window** if formatting is unavailable.

### Build output

`./scripts/build.sh` creates:

- `build/Install on Device.workflow` — the complete Quick Action with its embedded native helper.
- `dist/Install on Device.zip` — the packaged workflow for distribution after validation on the intended Macs.

Build output, local app samples, logs, and signing material are ignored by Git. Distribute the ZIP rather than committing binaries, and keep private app builds and device logs out of the repository.

### Tests

```sh
./tests/test.sh
```

The suite rebuilds the package, verifies signatures and property lists, tests discovery and connection logic, and exercises installation/removal of the workflow in a temporary directory. It does not modify your real Services folder or install a mobile app on a device.

- iOS tests use sanitized JSON fixtures and an injected clock for delayed readiness, cached or malformed responses, disappearing devices, deadlines, cancellation, explicit retry, and installation errors.
- Android tests use fake commands and time for AVD merging, multiple emulators, exact serial selection, delayed boot, unknown identities, startup failures, early process exit, deadlines, and cancellation.
- Additional checks cover literal command arguments and cancellation of a local sleep process.

GitHub Actions runs these tests on macOS when a pull request is opened, including drafts. Subsequent pushes do not trigger tests. To rerun manually, choose **Actions → Tests → Run workflow** and select the branch. Manual dispatch becomes available once the workflow is on the default branch.

End-to-end installation needs manual validation with compatible app builds:

- **iPhone:** close Xcode; test Wi-Fi with the phone unlocked, then locked and unlocked during the wait. Check an unreachable phone, cancellation, Retry, and USB.
- **Android:** install on a stopped AVD, then an already-running one. Cancel during boot and test with two emulators to confirm only the selected destination receives the app.
- **iOS Simulator:** install a simulator-built `.app` on stopped and running simulators and check an unavailable or incompatible destination.

These manual checks are not performed by the automated suite. CI does not prove actual wireless connectivity or emulator/simulator installation compatibility.

### Repository layout

```text
Sources/DeviceInstaller.swift   Native picker, discovery, installation, and self-tests
scripts/build.sh               Compile, sign, validate, and archive
scripts/package.py             Generate app and workflow metadata
scripts/install.sh             Install the built Finder action
scripts/uninstall.sh           Remove the installed Finder action
tests/test.sh                  Build, self-tests, and isolated lifecycle checks
tests/fixtures/                Sanitized iOS device responses
```

## License

This project is licensed under the [MIT License](LICENSE).
