# Incremental SwiftDial roadmap

Updated 2026-10-16. Diagnostics redaction, its tests the existing application UI translation to Brazilian Portuguese and removal of call-history limits are implemented; all other feature work below remains a proposal. Preserve the current AppKit UI and `Domain`/`UseCases`/adapter boundaries. See [ARCHITECTURE.md](ARCHITECTURE.md) for source findings and [BUILD.md](BUILD.md) for the baseline.

Complexity is relative: S = a focused component change, M = several components and tests, L = persistence or native/SIP integration with substantial validation. These are scope estimates, not delivery promises.

| Order | Increment | Complexity | Dependencies and affected components | Acceptance criteria |
| --- | --- | --- | --- | --- |
| 0 | Establish a repeatable native build and isolated runtime baseline | M | Exact pinned native libraries, project/toolchain settings; `README.md`, Xcode project and tests | App and all test targets compile; local test identity/data isolation agreed; synthetic/test-PBX calls validated. Fix only demonstrated compatibility errors, without a major dependency upgrade. |
| 1a | Safe diagnostic collection | M | `AKSIPUserAgent`, PJSUA logging configuration, application log location, new focused redaction tests | Authorization, Proxy-Authorization, passwords, tokens and URI userinfo never reach file, console or export; multiline/case-variant headers tested. Disable the native raw filename sink when routing through a sanitizer. PJSIP 2.10 callback delivery also depends on console level: verify the complete sink path. Keep disk writes off call/audio callbacks. |
| 1b | Structured SIP/local errors and native diagnostics UI | M | 1a; `AKSIPAccount`, `AKSIPCall`, callback adapters, `SIPResponseLocalization`, preferences and Help | Preserve PJ status separately from SIP response, account/call correlation and timestamp; show code plus actionable explanation, including unknown errors. Configurable levels, bounded log retention and user-initiated redacted export. No remote upload. Test bad credentials, DNS/TLS failures, busy, decline, timeout and local setup failure. |
| 2a | Ordered number transformations | M | Stable diagnostics; `AccountController.makeCallToURI`, `SanitizedCallDestination`, URI/number helpers, settings | A pure Foundation-based rule evaluator with validated regex/replacement, ordered application and explicit stop/continue semantics. Preserve SIP addresses and PBX `*`/`#` codes. Reject malformed output before dialing. Input/pattern limits and an execution policy prevent pathological regex from blocking the UI. |
| 2b | Rule editor, test and preview | M | 2a; preferences XIB/controller, localization and tests | Per-account ordered rules, add/remove/reorder, prefix insert/remove, inline errors, original/final-number preview and non-dialing test action. Audit manual dialing, contacts, history, URL/services, transfer and redial. Store original versus transformed destination deliberately so redial never applies a prefix twice. |
| 3a | Durable call outcomes | M | Structured errors from 1b; `Call` protocol/adapters, `CallHistoryRecord`, disconnect event target and storage | Store incoming/outgoing/missed/failed outcome, timestamps, duration and optional SIP/PJ failure. Record failures that occur before a native call object exists. Backward-compatible migration fixtures and loss-resistant load/save failures. |
| 3b | Uncapped searchable history | L | 3a; history protocols/factories, persistence adapter, `CallHistoryViewController` | Native indexed store (evaluate SQLite or Core Data behind the existing boundary), paged search by number/name/date/outcome and no arbitrary record cap. Migrate existing plists transactionally, retaining backups on failure. Separate retention from paging; test large datasets, disk-full, corrupt data and interrupted migration. The history purchase gate and 1,000-record retention cap have been removed. Search, paging and storage migration remain pending. |
| 4a | Reliable transfer flows | M | 1b plus existing attended flow; `AKSIPCall`, `CallTransferController`, callbacks and views | Add direct REFER transfer using the existing PJSIP API; preserve attended transfer. Clearly show progress and failure, retain the original call when appropriate, restore hold on cancel, test remote hangup races and PBX rejection. |
| 4b | Extension/pickup actions and shortcuts | S–M | Rule evaluation and 4a; account preferences and native call controls | Configurable PBX feature codes using ordinary dialing, no assumed universal pickup code. Keyboard-accessible actions, predictable focus and no accidental dialing from preview/settings. Validate against the selected test PBX. |
| 5 | Native UI polish and targeted API migration | M | Stable preceding flows; AppKit controllers/XIBs, colors, notifications and contact adapters | Compact windows, semantic native colors in dark/light modes, VoiceOver labels, keyboard navigation and clear status text. Migrate deprecated APIs in small independent changes. No wholesale SwiftUI rewrite or UI framework dependency. |
| 5a | Brazilian Portuguese (PT-BR) translation | M | Existing localization resources, AppKit XIBs, preferences, call status/error messages and new diagnostics copy | Add `pt-BR` resources using the existing localization system. Translate menus, preferences, call controls, diagnostics and accessibility text; verify terminology, pluralization, date/number formatting and layout with Brazilian Portuguese selected. Preserve SIP codes and technical identifiers. Existing UI translation implemented in 22 PT-BR resource files; future diagnostics UI copy remains part of step 1b. Build and localization resource checks passed; full visual and live-call validation remain pending. |

Accessibility, error handling and native visual conventions apply to every increment; they are not deferred until step 5. Fix concrete reliability defects from the assessment in small reviewed changes alongside the baseline, particularly audio buffer cleanup, media-state guards, Unicode parser byte counts and history load recovery. Do not mix these into a large refactor.

## Recommended first implementation task

The arm64 baseline builds after installing the pinned dependencies. The first authorized increment is the pre-sink diagnostics sanitizer and its tests, before exposing higher log levels. It replaces PJSIP's raw file sink with a shared sanitized file/console writer, omits credential-bearing records and message bodies, and removes URI contents. File writes run on a serial queue outside the SIP callback. This deliberately favors omission over incomplete credential redaction; it does not anonymize all names, hosts or IPs. Existing log files are not retroactively sanitized. Structured failures, logging preferences, retention and export remain pending review.

This redaction increment is implemented in `Telephone/SIPLog.m` and covered by eight tests in `TelephoneTests/SIPLogTests.m`, including native SRTP `key=` diagnostics. Validation: arm64 Debug app build succeeded; all 118 TelephoneTests passed (72 XCTest and 46 Swift Testing). No live SIP/PBX test was run. The existing UI has also been translated to Brazilian Portuguese; other roadmap features remain pending.

## Decisions requiring review before implementation

1. SwiftDial bundle ID, signing team, naming and data/Keychain migration policy. The current identity overlaps the installed Telephone app; keep runtime testing isolated until decided.
2. Resolved: one edition with all existing features. StoreKit, purchase prompts, receipt validation and Pro references have been removed. Every user has full history and the existing 30-call capacity.
3. Keep the current macOS 15.6 minimum, and is Intel distribution required? The M3 baseline is arm64; universal dependencies require separate validation.
4. Choose test provider/PBX and synthetic accounts for TLS/SRTP, transfer and pickup validation; define expected TLS/plain-RTP compatibility without weakening verification.
5. Initial dial-plan behavior implemented: optional per-account MicroSIP digit-map syntax, first match wins, unmatched numbers blocked, preview without calling. History calls apply the plan and preserve recognized outputs of its ordered rules; explicit SIP addresses and call-window redial bypass rewriting. No emergency/service-code exemption; include needed codes in the plan. Arbitrary regex and chained transformations remain outside this increment.
6. Agree diagnostic retention and personal-data redaction (numbers, names, hosts and IPs) separately from mandatory credential removal. The history itself remains local personal data with user-controlled deletion and no arbitrary cap.

These are review decisions, not requests to start feature development. No commits, pushes or pull requests were created.

## Call-history limits removed

All stored history is now shown without a purchase, and adding or reloading records no longer discards entries at 1,000. The existing plist format and manual deletion are preserved. Previously discarded records cannot be recovered. Regression coverage checks display of 1,001 records without a purchase prompt and persistence/reload through 1,002 records. The arm64 Debug app build and both TelephoneTests and UseCases test suites passed.

The current storage still loads the complete history and rewrites it on changes. Very large histories can become slower; paging and a database remain separate future work.

## Single edition

The app no longer includes a store, subscriptions, purchase reminders, receipt validation or Pro menus. All users receive the existing 30 simultaneous-call capacity and unrestricted history. Purchase-only code, tests, localization resources and the In-App Purchase capability were removed. This does not implement other roadmap features.

## MicroSIP-compatible dial-plan increment

Settings → Accounts → Advanced → Dial plan opens the per-account editor. Paste a plan, test a number without calling, then Save. Empty disables the plan; no plan is automatically enabled on existing accounts.

Supported syntax: `|`, optional outer parentheses, `x`, digit sets/ranges such as `[2-9]`, literal dial characters, `<from:to>` (including insertion/deletion), and `.` for zero or more occurrences of the preceding character. Rules are matched against the whole number in order. This is a bounded digit-map evaluator, not a general-purpose regex engine. Plans are limited to 2,048 characters, 64 alternatives and 128 atoms per alternative; numbers and results to 128 characters.

User example: `xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x.`

- `118`, eight/nine-digit local numbers, `0800…` and `0300…` pass unchanged.
- `04133334444` becomes `0434133334444`. The final dot is part of the rule.
- An earlier match takes priority: `012` stays `012`.
- Unmatched numbers are blocked; there is no automatic emergency-number bypass.

The shared outgoing-call entry point handles manual input, keypad, telephone contacts, telephone URL/service input and new transfer calls after number normalization and before the existing plus substitution. History calls apply the plan, recognizing already-transformed numbers by reversing substitutions and verifying the original against the ordered plan. This prevents duplicate prefixes for the current plan, including older records whose host was stripped. Explicit SIP addresses and call-window redial retain their routed destination. The history file contains no original dial input or plan version: an incoming number identical to a valid transformed output is treated as already transformed, and results of a different previous plan cannot always be recognized. This does not change in-call DTMF.

Validation: arm64 app build and 124 Telephone tests passed (78 XCTest + 46 Swift Testing). No live PBX calls were made. MicroSIP syntax reference: https://www.microsip.org/help.

## Internal contacts

Local Contacts (Command-Shift-K) stores a global SwiftDial-only list with name and original number in app preferences. Create, edit and delete are available; saving never applies the dial plan. Existing macOS Contacts remain a fallback. Local matches identify incoming call windows/notifications, outgoing calls and history; saved edits refresh visible history.

Matching first compares normalized original numbers (including Brazilian +55 variants), then derives aliases using the selected account's current dial plan and plus substitution. Ambiguous aliases do not select a name. No last-digit-only matching is used for internal contacts. Numbers transformed by an older plan, or rewritten differently by the PBX, may not match. No contacts are synchronized or written to macOS Contacts.

History now offers **Save Contact…** on the clicked/selected row. It opens an editable draft and saves only when Save is pressed. Existing local contacts are opened for editing. Outgoing numbers recover a unique leading prefix replacement verified against the account's current ordered plan (and undo configured plus substitution); incoming caller IDs are left unchanged unless a saved contact already supplies the original number. Ambiguous prefixes are retained for manual review. Old plan versions are not stored, so recovered outgoing numbers show a reminder to check the original number. SIP usernames cannot be saved as phone numbers. Validation: arm64 app build and 137 Telephone tests passed; no live calls made.

Double-clicking a saved Local Contacts row now calls its stored number through the existing normal dialing path (including registration, normalization and the account dial plan). As with URL/service dialing, the first enabled account is used. The contact and unsaved form edits are not saved or rewritten by dialing; clicks outside a row do nothing. If calling is unavailable, the editor shows a message. Validation: arm64 build and 139 Telephone tests passed using fake call callbacks; no live calls placed.
