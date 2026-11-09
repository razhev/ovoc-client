<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="OVoC Client icon">
</p>

# OVoC Client

English · [Русский](README.ru.md)

[![CI](https://github.com/razhev/ovoc-client/actions/workflows/ci.yml/badge.svg)](https://github.com/razhev/ovoc-client/actions/workflows/ci.yml)

A small native iOS app that connects an iPhone to your own OpenVPN over Cloak server, for example
one set up with [AmneziaVPN](https://amnezia.org). The app has no servers, accounts or analytics
of its own. You add your key; it gives you a Connect button.

Cloak wraps OpenVPN traffic in what looks like an ordinary HTTPS session, so the connection is
hard to tell apart from a visit to a regular website.

## What it does

- Imports an Amnezia `vpn://…` key, pasted or opened as a file. The key stays on the phone,
  inside the iOS VPN configuration.
- Connects and disconnects with one button and describes each state in plain words.
- Can keep selected Russian services (banks, marketplaces, government portals) outside the
  tunnel. All exceptions are off until you turn them on.
- Shows the tunnel log on its own screen and shares it in one tap.
- Has a Russian and an English interface.

## Install

The app is distributed through TestFlight: [join the beta](https://testflight.apple.com/join/KMXkHFyz).
It needs an iPhone with iOS 16 or newer and the TestFlight app. The current build is 0.1.0 (15)
from 2026-10-17; [CHANGELOG.md](CHANGELOG.md) lists what changed in each build.

It is not in the App Store. Apple's guideline 5.4 accepts VPN apps only from organizations, and
the Russian storefront removes such clients on request.

You also need a server. Any OpenVPN over Cloak server will do; the simplest route is a
self-hosted AmneziaVPN with a key exported for the "OpenVPN over Cloak" protocol.

## Build from source

You need a Mac with Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Go (the build
pins version 1.22.2 itself) and an Apple Developer account for the Network Extension entitlement.
VPN does not work in the Simulator, so an iPhone on a cable is required.

```bash
make framework   # build OpenVPNAdapter and Cloak from source with the project's patches
make test        # unit tests on the Mac
make install     # signed build onto the connected iPhone
```

The full list of commands, architecture notes and on-device debugging are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (in Russian).

## How it works

A SwiftUI app and one Network Extension. The extension runs Amnezia's fork of OpenVPNAdapter
with Cloak compiled in as the transport. The framework is built from source here, with a few
patches: the published binary did not write the GCM authentication tag, and the server dropped
every packet.

Key parsing lives in a local Swift package, `ConfigKit`. The app turns the key into a ready
OpenVPN profile and hands it to the extension through the VPN configuration; the extension
parses nothing itself.

## Documentation

Most documents are in Russian.

- [CHANGELOG.md](CHANGELOG.md) — changes by build.
- [PRIVACY.md](PRIVACY.md) — privacy policy, Russian and English.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — commands, architecture, debugging on the device.
- [docs/DEVICE-TESTING.md](docs/DEVICE-TESTING.md) — testing on an iPhone, symptoms and what to do.
- [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) — how a build gets to TestFlight.
- [docs/SERVICE-BYPASS-CATALOG.md](docs/SERVICE-BYPASS-CATALOG.md) — where the "Outside VPN" addresses come from.
- [docs/history/](docs/history/README.md) — the original plan and how it actually went.

## Feedback

If something does not connect, open an [issue](https://github.com/razhev/ovoc-client/issues/new/choose)
and attach the files from the Logs screen. They contain the server address but never the key;
remove the address if you prefer. Never paste the `vpn://` key itself.

Pull requests are welcome; [CONTRIBUTING.md](CONTRIBUTING.md) explains what fits the project and
how to build and test it. Report security problems privately, as described in
[SECURITY.md](SECURITY.md).

## License

GPL-3.0, see [LICENSE](LICENSE). The app includes AGPL-3.0 code from OpenVPNAdapter and
OpenVPN 3 and GPL-3.0 code from Cloak; the full list of components is in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

OpenVPN® is a registered trademark of OpenVPN Inc. OVoC Client is not affiliated with Amnezia
or OpenVPN Inc.
