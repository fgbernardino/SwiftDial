# SwiftDial architecture assessment

Assessment: 2026-10-16, repository revision `72bbb66dda0ad7a3568cf78ce349c7a61a4bf936`. This describes the checked-out fork, not an assumption about upstream Telephone. No application code was changed. Build and test evidence is in [BUILD.md](BUILD.md); feature coverage is in [SIP_CAPABILITIES.md](SIP_CAPABILITIES.md).

## Structure and design

The application is branded SwiftDial and builds as SwiftDial.app, retaining bundle ID `com.tlphn.Telephone`. It is a native AppKit application with Objective-C controllers and SIP adapters, Swift business logic, with no purchase UI. It is not a SwiftUI application requiring a rewrite.

| Layer / target | Responsibility | Main source entry points |
| --- | --- | --- |
| `Telephone` | AppKit presentation, composition, operating-system and SIP adapters | `Telephone/AppController.m`, `CompositionRoot.swift`, `AccountController.m`, `CallController.m`, `PreferencesController.m` |
| `UseCases` | Application operations and protocols: accounts, calls, history, contacts, audio selection, ringtone | `UseCases/UserAgent.swift`, `Call.swift`, `Account.swift`, `UserAgentStartUseCase.swift`, `CallHistoryCallEventTarget.swift` |
| `Domain` | Audio-device value objects, selection and fallback rules | `Domain/SystemAudioDevices.swift`, `SystemToUserAgentAudioDeviceMap.swift`, `PreferredSoundIO.swift`, `FallingBackSoundIO.swift` |
| Test doubles | Fakes and spies for the corresponding layers | `DomainTestDoubles/`, `UseCasesTestDoubles/` |
| Tests | XCTest and Swift Testing; pure logic and adapter/presenter tests | `DomainTests/`, `UseCasesTests/`, `TelephoneTests/`; some test sources also live alongside production sources, so target membership matters |
| Native libraries | Signaling, media, codecs and TLS | `ThirdParty/PJSIP/patches/`, dependency instructions in `README.md` |

`CompositionRoot` assembles protocol-based use cases, adapters, factories and decorators. `AppController` handles application startup, URL/services entry points and account windows. AppKit uses nibs/XIBs, delegates and notifications. Swift adapters turn Objective-C notifications into application event targets. History composes truncation, persistence, ordering and notification decorators. This is a useful existing separation; the older controllers nevertheless retain significant SIP orchestration and presentation responsibilities.

The app now has one edition: StoreKit, receipt validation, purchase reminders and Pro UI have been removed. UserAgentStartUseCase always enables the existing 30 concurrent-call capacity; history is unrestricted.

## SIP and call lifecycle

`AKSIPUserAgent.m/.h` wraps the PJSUA C API, owns its lifecycle, pool, transports, accounts, codecs and conference audio. It is a singleton. `AKSIPAccount.m` owns registration state and calls; `AKSIPCall.m` wraps answer, decline, hangup, DTMF, mute, hold and attended transfer. `Telephone-Bridging-Header.h` exposes these interfaces and PJSUA to Swift. This is the PJSUA C layer, not PJSUA2.

Startup creates PJSUA, configures callbacks, media, NAT settings and logging, creates IPv4/IPv6 UDP/TCP/TLS transports, and starts the stack. Account creation supplies a digest credential (realm, username and password) and registrar/proxy configuration. `AKKeychain.m` stores passwords in the macOS Keychain; account settings live in UserDefaults. Authentication failure UI is in `AuthenticationFailureController.m`. No real credentials were read during this assessment.

Outgoing calls enter through `ActiveAccountViewController`, `AppController` URL/services handling, contact/history adapters, transfer UI or redial. `AccountController.makeCallToURI` normalizes numbers, optionally replaces a leading `+`, supplies the account domain and creates a call controller. `AKSIPAccount.thread_makeCallWithParameters` invokes PJSUA on a dedicated thread, copies call information and completes on the main queue. Redial in `CallController` calls the account directly with its saved URI: future dial rules must explicitly avoid both bypass and double transformation here.

`PJSUAOnIncomingCall.m`, `PJSUAOnCallState.m`, `PJSUAOnCallMediaState.m`, `PJSUAOnAccountRegistrationState.m`, `PJSUAOnCallTransferStatus.m` and `PJSUAOnCallReplaced.m` translate native callbacks. `PJSUACallInfo.m` copies relevant C fields into Objective-C values before main-queue delivery. Notifications drive controllers and `AKSIPCallEventSource.swift`; use-case event targets update history, ringtone, music playback and user attention. Disconnect copies final status and duration, removes the call from the account and posts the disconnect event.

## Audio, contacts and persistence

Audio enumeration and change listeners are in `CoreAudioSystemAudioDevicesFactory.swift`, `CoreAudioDefaultSystemSoundIOFactory.swift`, `CoreAudioChangeEventSource.swift` and the corresponding change-event sources. `UserAgentAudioDevices.swift` enumerates PJSUA devices. Domain mapping matches system and SIP devices, while `UserAgentSoundIOSelectionUseCase`, `PreferredSoundIO` and `SystemDefaultingSoundIO` select preferred/fallback input and output. Ringtone output is independently controlled by ringtone use cases and NSSound adapters. `AKSIPUserAgent.updateAudioDevices` temporarily selects a null device, deinitializes and reinitializes media devices; subsequent selection must restore sound.

History is already persistent. `CompositionRoot.swift` builds `NotifyingCallHistoryFactory → ReversedCallHistoryFactory → PersistentCallHistoryFactory → TruncatingCallHistoryFactory()`. `CallHistoryCallEventTarget` records disconnected calls. `CallHistoryRecord` contains URI, date, duration, incoming and missed flags; it lacks a distinct failed-call outcome and SIP failure fields. `PersistentCallHistory` loads/saves an entire property-list array through `SimplePropertyListStorage`, which uses atomic file writes. Files are grouped by account UUID under `Application Support/<bundle ID>/CallHistories`, within the container when sandboxed. Account removal triggers history deletion. History has no retention or purchase-based display cap. There is no dedicated history search in the inspected view controller.

Modern contact matching uses `CNContactStoreToContactsAdapter`, `LazyDiscardingContactMatchingIndex`, `SimpleContactMatchingIndexFactory` and `CNContactStoreContactsChangeEventSource`. Significant-number-length matching is configurable. Older autocomplete and labels in `ActiveAccountViewController` and `AKAB*` still use AddressBook. Contact access failure is logged; it does not establish that permission prompts or denial UX work correctly on the current machine.

## Settings, logging and errors

`DefaultAppSettings.swift`, `UserDefaultsKeys.swift`, `AKSIPAccountKeys.swift`, `SettingsMigration*`, `TCPTransportSettingsMigration` and `IPVersionSettingsMigration` define defaults and migrations. Preference controllers and localized XIBs expose general, account, network and sound settings. Advanced keys include DNS SRV, STUN, ICE, QoS, VAD, codec restrictions, contact/Via/SDP rewrites and log levels; a stored key does not imply a visible preference control.

PJSUA writes `Telephone.log` under `Application Support/<bundle ID>/Logs`, resolved through `LogFileURL` and application-data-location adapters. Default file level is 3, console level 0. `HelpMenuActionTarget` reveals the log and copies settings. `SIPResponseLocalization.m` plus localized `SIPResponses.strings` maps known SIP statuses; `AccountController` and `CallController` display registration/call errors. Other paths use NSLog, print or Boolean failure and lose structured details. A local failure in `thread_makeCallWithParameters` collapses the PJSUA status to success/failure before UI delivery.

## Prioritized debt and risks

These are source findings and validation gaps, not claims of observed live-call failures.

| Priority | Finding and evidence | Impact / minimum follow-up |
| --- | --- | --- |
| High | Raw SIP logging has no application redaction boundary. `AKSIPUserAgent` assigns a PJSUA log filename; pinned `pjsua_core.c` writes raw messages to that file before calling a custom logger. | Increased logging can persist Authorization/Proxy-Authorization and personal routing data. Redact before every sink; merely sanitizing export or installing a callback while retaining the raw file sink is insufficient. Do not enable verbose real-account logs for baseline testing. |
| High | History load errors are only printed in `PersistentCallHistory.load`; the in-memory origin stays empty and a later add saves it back. | An unreadable/corrupt history can be replaced by a new partial history. Preserve failed-load files and report storage failures before extending history. Atomic writes protect replacement integrity, not this recovery path. |
| High | `PJSUAOnCallMediaState` ignores `pjsua_call_get_info` status and reads `media[0]` without testing `media_cnt`; mute/unmute also assume a valid first audio slot. | Failure or a no-media transition may use invalid/stale media state. Add guarded status/count/type checks and targeted tests before call-control expansion. |
| Medium | `UserAgentAudioDevices.makeDevices` allocates a buffer, then calls a throwing function before deallocation. | Enumeration failure leaks the buffer. A scoped `defer` is the minimal later fix. Enumeration is also capped at 32 devices. |
| Medium | `AKSIPURIParser` passes UTF-8 bytes to PJSIP with NSString character length instead of UTF-8 byte length. | Non-ASCII display names/URIs can be truncated or rejected. Test with synthetic Unicode input and correct the byte-count boundary. |
| Medium | `PJSUAOnCallState.LogCallDump` has a static buffer and temporarily changes global logging decoration. `WaitingThread`, native callbacks, main-queue work and Swift actors coexist. | Concurrent callback safety needs stress testing; do not assert a proven race without reproduction. `@unchecked Sendable` formatters and `nonisolated(unsafe)` FileManager fields deserve narrow ownership review. |
| Medium | `AccountController` retries with a fixed NSTimer interval and reachability-driven registration; `AKNetworkReachability` checks reachability, not provider health. | Wi-Fi/VPN changes, sleep/wake and stale registered transports require live tests. No use of PJSUA's IP-change handling API was found. Existing reconnection support is present, but robust recovery is unproven. |
| Medium | Device refresh temporarily disconnects audio, ignores several native return codes and relies on a later selection event. | Test unplug/replug, Bluetooth profile changes and default-device changes during calls; retain fallback logic. |
| Medium | Legacy `NSUserNotification`, AddressBook, `SCNetworkReachability*` and `SecKeychain*` APIs remain. The successful app build emits notification, reachability and Keychain deprecation warnings. | Plan focused native migrations only when required, preserving permission and credential migration behavior. ARC is enabled, but C allocations and CF ownership still need manual care. |
| Medium | Old pinned native dependency stack, local Darwin patches and bundled `PublicCAs.pem`. | Reproducible builds, dependency advisory review and CA trust freshness are release prerequisites. No exhaustive vulnerability or certificate audit was performed. Preserve TLS verification; do not bypass certificate errors. |
| Medium | History loads and rewrites all records and contact matching processes full result sets. | Removing the cap alone does not provide scalable unlimited history. Introduce indexed/paged storage behind existing protocols when implementing Priority 3. |
| Medium | Telephone identity, Keychain service naming and storage paths remain. | A test launch under the old identity can interact with existing Telephone data. Use an isolated macOS test user for runtime validation until a migration policy is approved. |

The existing test suites cover device selection, URI/number handling, history decorators, settings, event propagation, presenters, ringtone and full-capacity startup. They do not prove real registrar, TLS, RTP, NAT, device-hotplug or sleep/wake behavior. No SIP-server integration fixture or end-to-end call harness was found. See BUILD for executed test counts and blockers.

## Licensing and distribution

`LICENSE` contains GPL v3; source notices offer GPL v3 or later. Preserve notices, license text and source availability when distributing. PJSIP's pinned source offers GPL v2 or later; bundled codecs, SRTP and TLS libraries have their own notices. Keep an inventory of the exact built artifacts and licenses rather than assuming one license covers everything. Distribution, signing, trademark/product identity require review; this assessment is not a legal clearance. No cloud service or telemetry was introduced.
