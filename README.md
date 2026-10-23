# Clamshell

A free, open-source emulator for a classic dual-screen handheld, built natively in Swift and
SwiftUI for the foldable iPhone Duo. Hold the phone half-folded and it becomes a clamshell:
the top screen above the fold, the touch screen below.

Clamshell runs the [melonDS](https://melonds.kuribo64.net) core as an interpreter (no JIT).

## Features

- Layouts for every posture: half-folded, fully open (stacked or side by side) and closed,
  on the cover screen. Also runs on other iPhones and on iPad.
- Touch and Apple Pencil on the touch screen, on-screen controls, game controllers and
  keyboards.
- Battery saves, save states, and Continue to pick up where you left off.
- Microphone (or a "blow" button), rumble haptics, and folding the device to close the
  lid.
- Find Homebrew: links to free original games on their authors' own pages.

Clamshell does not include any games, BIOS or firmware. It boots with the free FreeBIOS
replacement, and plays homebrew or games you have the right to use.

## Building

Requires Xcode 27.2 or later (iOS 27.1 SDK), CMake and Ninja.

```sh
git clone --recurse-submodules https://github.com/orionpaxnemesisprime-tech/Clamshell.git
cd Clamshell
brew install cmake ninja
xcodebuild -downloadComponent MetalToolchain
Scripts/build-core.sh
open Clamshell.xcodeproj   # scheme: Clamshell
```

Core tests: `swift test --package-path Packages/ClamshellCore`.

The optional tip jar uses [RevenueCat](https://www.revenuecat.com). It's hidden unless you
set the `REVENUECAT_API_KEY` build setting to a RevenueCat public SDK key.

## Supporting Clamshell

Clamshell is free and stays free. If you'd like to support its development, you can
[sponsor it on GitHub](https://github.com/sponsors/orionpaxnemesisprime-tech) or leave a tip in
the app (Settings › Support Clamshell). Tips don't unlock anything.

## Licence

Clamshell is free software under the [GNU General Public License v3](LICENSE).
Third-party components and their licences are listed in
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

Clamshell is not affiliated with, endorsed by, or sponsored by Nintendo. All trademarks
belong to their respective owners. Clamshell does not include any games; you must supply
software you have the right to use.
