# Build environment and baseline validation

Assessment date: 2026-10-16. Source revision: `72bbb66dda0ad7a3568cf78ce349c7a61a4bf936`. Commands run from `/Users/fgbernardino/SwiftProjects/SwiftDial` unless specified. No app source/project configuration was edited, and nothing was committed or pushed.

**The unchanged application builds successfully for arm64 on this M3.** The minimum required setup was a per-command Xcode override plus local builds of the three pinned native dependencies. No application code correction or dependency upgrade was needed. The output is an unsigned Debug build, not a release-ready signed application.

## Environment

| Item | Observed value |
| --- | --- |
| Hardware | Apple M3, arm64 (confirmed using `sysctl`) |
| Host OS | macOS 27.0.1, build 26A434 (reported by `sw_vers`) |
| Installed Xcode | `/Applications/Xcode.app`, Xcode 27.1, build 27A9275 |
| Selected developer directory | `/Library/Developer/CommandLineTools`; plain `xcodebuild` fails because full Xcode is not selected |
| Working override | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global selector change made |
| SDK | MacOSX27.0.sdk |
| Swift compiler | Apple Swift 6.4; project language mode `SWIFT_VERSION = 6.0` |
| Minimum deployment target | macOS 15.6, in project settings and README C compiler flags |
| Concurrency | Complete strict checking and approachable concurrency enabled in project configurations |
| Product | Telephone 1.6, build 143; bundle `com.tlphn.Telephone` |

The native Apple Silicon target is suitable for M3 in architecture terms; this is not evidence of working audio or SIP hardware behavior. The README requests universal arm64+x86_64 libraries. This baseline builds native arm64 only and passes `ARCHS=arm64` to Xcode. Intel/universal and macOS 15.6 runtime compatibility remain unverified. No Swift Package Manager, CocoaPods or Carthage dependency manifest was found.

## Xcode configuration and signing

`Telephone.xcodeproj/project.pbxproj` defines Telephone, Domain, UseCases, their test targets and test doubles. Shared schemes include Domain, UseCases, UseCasesTests and test-double schemes; there is no checked-in shared Telephone app/test scheme. Xcode lists an automatically available Telephone scheme, but attempting its test action fails with `Scheme Telephone is not currently configured for the test action`. Use `-target Telephone` for the build, and the existing Domain/UseCases schemes for tests. A temporary external workspace with a TelephoneTests test scheme was created under `/private/tmp/swiftdial-validation.xcworkspace` for validation; no repository scheme was added.

The app uses automatic SDK selection, ARC, hardened runtime, App Sandbox, network client/server and audio-input settings. The explicit entitlements file adds microphone and music/Spotify automation permissions; Xcode also generates entitlements from build settings, so reading that file alone is not the complete signing picture. `Info.plist` contains microphone, contacts and Apple-events purpose strings. The project carries team `B5WSA37RY8` and `Mac Developer` identity. Local compilation uses `CODE_SIGNING_ALLOWED=NO`; distribution needs the user's signing identity and verified effective entitlements. Unsigned compilation does not validate permissions, notarization or launch behavior.

An installed `/Applications/Telephone.app` was observed but not launched or used as proof that this source builds. The fork still shares Telephone's bundle identity and data paths. Runtime testing should use an isolated macOS user until identity/migration is decided.

## Dependencies and exact reproduction

Initially `ThirdParty` contained only three PJSIP patches, with no installed headers or libraries. Dependencies were downloaded at the exact README versions. All three original archive URLs returned HTTP 200 from this machine after running with network access outside the restricted sandbox.

| Dependency | Version | Source | Required location |
| --- | --- | --- | --- |
| Opus | 1.3.1 | [Mozilla archive](https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz) | `ThirdParty/Opus/include`, `lib/libopus.a` |
| LibreSSL | 3.1.5 | [OpenBSD archive](https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.1.5.tar.gz) | `ThirdParty/LibreSSL/include`, `lib/libssl.a`, `lib/libcrypto.a` |
| PJSIP / pjproject | 2.10 | [Pinned GitHub archive](https://codeload.github.com/pjsip/pjproject/tar.gz/2.10) | `ThirdParty/PJSIP/include/pjsua-lib/pjsua.h`, `lib/*-arm-apple-darwin.a` |

The README calls Opus optional, but both application build configurations explicitly link `-lopus`. Omitting it also requires a deliberate linker/configuration adjustment. Building the pinned version is the smallest baseline choice. PJSIP additionally builds bundled SRTP, GSM, Speex, iLBC and resampling libraries. It disables video, libyuv and libwebrtc.

Build prerequisites are full Xcode/SDK, a C/C++ compiler, make, shell, curl, tar and patch. The README recommends LibreSSL detached-signature verification with GPG and an independently trusted release key. Archive download success and locally calculated hashes do not replace that verification; release signature/key validation was not performed here. Do that before distributing these binaries.

Observed archive SHA-256 values (download identity, not independent authenticity verification):

```text
opus-1.3.1.tar.gz       65b58e1e25b2a114157014736a3d9dfeaad8d41be1c8179866f144a2fb44ff9d
libressl-3.1.5.tar.gz   2c13ddcec5081c0e7ba7f93d8370a91911173090f1922007e1d90de274500494
pjproject-2.10.tar.gz  936a4c5b98601b52325463a397ddf11ab4106c6a7b04f8dc7cdd377efbb597de
```

The following native-arm64 procedure preserves pinned versions. Run configure/make commands from fresh extracted source directories. `rtk proxy` preserves raw tool behavior, per the workspace instructions.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SWIFTDIAL_ROOT=/Users/fgbernardino/SwiftProjects/SwiftDial

# Download into a temporary directory, then extract there.
rtk proxy curl -fLO https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz
rtk proxy curl -fLO https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.1.5.tar.gz
rtk proxy curl -fL -o pjproject-2.10.tar.gz https://codeload.github.com/pjsip/pjproject/tar.gz/2.10
```

Extract the archives and build:

```sh
rtk proxy tar xzf opus-1.3.1.tar.gz
rtk proxy tar xzf libressl-3.1.5.tar.gz
rtk proxy tar xzf pjproject-2.10.tar.gz

# In opus-1.3.1:
rtk proxy ./configure --prefix="$SWIFTDIAL_ROOT/ThirdParty/Opus" --disable-shared CFLAGS='-arch arm64 -Os -mmacosx-version-min=15.6'
rtk proxy make -j4
rtk proxy make install

# In libressl-3.1.5:
rtk proxy ./configure --prefix="$SWIFTDIAL_ROOT/ThirdParty/LibreSSL" --disable-shared CFLAGS='-arch arm64 -Os -mmacosx-version-min=15.6'
rtk proxy make -j4
rtk proxy make install
```

In `pjproject-2.10`, create `pjlib/include/pj/config_site.h` with exactly:

```c
#define PJSIP_DONT_SWITCH_TO_TCP 1
#define PJSUA_MAX_ACC 32
#define PJMEDIA_RTP_PT_TELEPHONE_EVENTS 101
#define PJ_DNS_MAX_IP_IN_A_REC 32
#define PJ_DNS_SRV_MAX_ADDR 32
#define PJSIP_MAX_RESOLVED_ADDRESSES 32
#define PJ_HAS_IPV6 1
```

Then run:

```sh
rtk proxy patch -p0 -i "$SWIFTDIAL_ROOT/ThirdParty/PJSIP/patches/sock_qos_darwin.patch"
rtk proxy patch -p0 -i "$SWIFTDIAL_ROOT/ThirdParty/PJSIP/patches/os_core_unix.patch"
rtk proxy patch -p0 -i "$SWIFTDIAL_ROOT/ThirdParty/PJSIP/patches/coreaudio_dev.patch"
rtk proxy ./configure --prefix="$SWIFTDIAL_ROOT/ThirdParty/PJSIP" \
  --with-opus="$SWIFTDIAL_ROOT/ThirdParty/Opus" \
  --with-ssl="$SWIFTDIAL_ROOT/ThirdParty/LibreSSL" \
  --disable-video --disable-libyuv --disable-libwebrtc --host=arm-apple-darwin \
  CFLAGS='-arch arm64 -Os -DNDEBUG -mmacosx-version-min=15.6' \
  CXXFLAGS='-arch arm64 -Os -DNDEBUG -mmacosx-version-min=15.6'
rtk proxy make dep
rtk proxy make -j4 lib
rtk proxy make install
```

All three repository patches applied cleanly: QoS disables `SO_NET_SERVICE_TYPE` selection, semaphore handling uses dispatch semaphores, and CoreAudio no longer advertises/reads output-volume capability in the patched sections. PJSIP configure detected LibreSSL through its OpenSSL-compatible interface and found Opus. Neither successful configure nor one CPU slice proves a universal build. Preserve the `arm-apple-darwin` library suffix expected by the project or explicitly reconcile linker names later.

Local dependency installs are covered by existing `.gitignore` rules. Source archives and extracted build trees reside under `/private/tmp/swiftdial-deps`; they are temporary, not vendored source. No Homebrew package or global Xcode setting was changed.

## App build and test commands

```sh
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Telephone.xcodeproj -target Telephone -configuration Debug \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/private/tmp/swiftdial-baseline/products \
  OBJROOT=/private/tmp/swiftdial-baseline/objects build

rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Telephone.xcodeproj -scheme Domain -destination platform=macOS \
  -derivedDataPath /private/tmp/swiftdial-domain CODE_SIGNING_ALLOWED=NO test

rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Telephone.xcodeproj -scheme UseCases -destination platform=macOS \
  -derivedDataPath /private/tmp/swiftdial-usecases CODE_SIGNING_ALLOWED=NO test

rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Telephone.xcodeproj -target TelephoneTests -configuration Debug \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/private/tmp/swiftdial-telephone-tests/products \
  OBJROOT=/private/tmp/swiftdial-telephone-tests/objects build
```

The last command compiles the TelephoneTests target; it does not execute tests. To execute that suite with Xcode, configure a scheme containing TelephoneTests in its Test action. This run used a temporary workspace referencing the original project by absolute path and a `TelephoneBaseline` scheme referencing target ID `AA3FAB841BBAAE630064B2C3`, with TelephoneTests enabled in both Build-for-Testing and Test actions:

```sh
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace /private/tmp/swiftdial-validation.xcworkspace \
  -scheme TelephoneBaseline -destination platform=macOS \
  -derivedDataPath /private/tmp/swiftdial-telephone-suite \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 \
  SYMROOT=/private/tmp/swiftdial-telephone-tests/products \
  OBJROOT=/private/tmp/swiftdial-telephone-tests/objects test
```

The temporary scheme can be recreated using Xcode's Manage Schemes interface with TelephoneTests selected; its absolute reference is specific to this checkout.

## Validation results

- Domain: **25 XCTest tests passed**, no failures.
- UseCases: **169 XCTest tests plus 90 Swift Testing tests passed**, no failures.
- TelephoneTests: **64 XCTest tests plus 46 Swift Testing tests passed**, no failures, through the temporary external workspace. Total across the three suites: **394 tests passed**.
- Initial app compilation: failed in `Telephone-Bridging-Header.h:5` because `pjsua-lib/pjsua.h` was absent.
- Restricted sandbox attempts also hit module-cache access and `com.apple.testmanagerd.control` errors. Retrying with authorized local service/cache access allowed the two Swift suites to run. These sandbox failures are not application test failures.
- Opus 1.3.1, LibreSSL 3.1.5 and patched PJSIP 2.10: configured, compiled and installed successfully. `lipo -archs` confirms arm64 for the installed Opus, SSL and PJSUA archives. Existing ignore rules were checked with `git check-ignore`.
- Final app build: **BUILD SUCCEEDED**. Output: `/private/tmp/swiftdial-baseline/products/Debug/Telephone.app`. No source edits were required.
- TelephoneTests target: **BUILD SUCCEEDED** after dependencies were installed; the subsequent temporary-workspace test action reported **TEST SUCCEEDED**.

The app build reported 35 warning lines, including deprecated `SecKeychain*`, `SCNetworkReachability*` and `NSUserNotification*` APIs plus a skipped AppIntents metadata extraction notice. They did not prevent compilation. No unresolved compiler/linker error remains in the tested arm64 Debug build; Release, Intel and signed builds are not claimed.

Test results are under `/private/tmp/swiftdial-domain/Logs/Test/`, `/private/tmp/swiftdial-usecases/Logs/Test/` and `/private/tmp/swiftdial-telephone-suite/Logs/Test/`. Final logs are `/private/tmp/swiftdial-build-final.log`, `/private/tmp/swiftdial-telephone-tests-final.log`, `/private/tmp/swiftdial-telephone-suite-final.log`, and `/private/tmp/swiftdial-{opus,libressl,pjsip}.log`. Temporary files may disappear after system cleanup; essential outcomes are captured here.

## Runtime validation still required

Use a dedicated macOS test user and synthetic provider/PBX credentials. Check microphone/contacts denial and grant, inbound/outbound audio, UDP/TCP/TLS with certificate verification, SRTP compatibility, DTMF, hold/resume, attended transfer, multiple accounts, wake/reconnect and device hotplug. Check dark/light mode, keyboard focus and VoiceOver. Exercise history corruption and write failures with disposable fixtures. No actual accounts, Keychain secrets or Telephone user data were inspected or changed. No app launch, SIP call, hardware audio validation, signing or distribution test was performed.

Release readiness also needs a dependency/security-advisory review, license/notice inventory and verification of the bundled CA set. This assessment neither upgrades old dependencies nor certifies their security.
