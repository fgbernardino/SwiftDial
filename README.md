Telephone is a VoIP SIP softphone for Mac. It allows you to make phone
calls over the Internet or your company network. If your phone line
supports SIP protocol, you can use it on your Mac instead of a
physical phone anywhere you have a decent network connection.

## SwiftDial changelog

### Current changes

- **Updated deprecated components:** replaced legacy Keychain APIs with `SecItemCopyMatching`, `SecItemAdd`, and `SecItemUpdate`, and replaced deprecated network reachability APIs with Apple's Network framework path monitor.
- **Local contacts:** save, edit, delete, and call contacts stored locally in SwiftDial, separately from macOS Contacts and the shared User Directory. Saved names appear in calls and call history. Phone numbers retain their original values; the dial plan is applied when calling. Contacts can also be saved from call history.
- **Brazilian Portuguese (PT-BR):** added translations for menus, preferences, account setup, call windows, call history, contacts, directory, and dial-plan controls.
- **Expanded call history:** retain 1,000 records and beyond per account. The current implementation has no fixed record cap and persists history between launches.
- **User Directory sync:** added a read-only shared directory using the MicroSIP-style JSON response described below, with automatic refresh, manual refresh, local caching, and calling from the directory. Local contacts remain separate and take precedence when matching names.
- **Dial plan:** added per-account MicroSIP-style digit-map rules for matching and rewriting outgoing numbers, with validation and a **Test without calling** action. See the syntax and example below.
- **Improved call windows:** show the contact name, formatted phone number, call status, and a separate elapsed-time display (`MM:SS`, or `HH:MM:SS` for longer calls). Added visible **Mute / Unmute** and **Transfer…** buttons alongside **End Call**. Mute and transfer are enabled once the call connects; transfer is disabled during remote hold and opens the transfer sheet, placing the call on local hold if needed. Typed DTMF digits are displayed during a call and reset when redialing.

### User Directory JSON example

Open **Local Contacts → User Directory…**, enter an HTTPS endpoint URL, and choose **Save URL**. The endpoint should return JSON in this format:

```json
{
  "refresh": 300,
  "items": [
    { "name": "Reception", "number": "100" },
    { "name": "Support", "number": "101" },
    { "name": "Curitiba Office", "number": "04133334444" }
  ]
}
```

`items` contains contacts with a nonempty `name` and a valid phone `number`. Numbers must be JSON strings to preserve leading zeros, and duplicate numbers are rejected. `refresh` is an optional interval in seconds: positive values are limited to 30–86,400 seconds; an omitted, zero, or negative value disables periodic refresh after a successful fetch. **Refresh** fetches the directory manually. Failed updates retain the last valid cached directory and retry after five minutes. Leave the URL empty to disable the directory.

### MicroSIP-style dial-plan example

Configure the dial plan in the account preferences. SwiftDial supports MicroSIP-style digit maps, not unrestricted regular expressions:

| Syntax | Meaning |
| --- | --- |
| `x` | Match one dialing character (`0`–`9`, `+`, `*`, or `#`). |
| `.` | Repeat the preceding character or character set zero or more times. |
| `[2-9]` | Match a character from a set or numeric range. |
| `\|` | Separate rules; the first full match wins. |
| `<old:new>` | Replace matched text; `<:new>` inserts and `<old:>` removes it. |
| `(…)` | Optionally wrap the entire plan. |

```text
xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x.
```

This example keeps three-character extensions, eight- and nine-character numbers, and numbers starting with `0800` or `0300` unchanged. Otherwise, a leading `0` is replaced with `043`: `04133334444` becomes `0434133334444`.

Numbers that match no rule are blocked. An empty plan disables this feature. Rules run before the account's `+` substitution. History dialing avoids repeating recognized replacements; explicit SIP addresses and call-window redial use the stored destination.

## Building

### Opus

Opus codec is optional.

Download:

    $ curl -O https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz
    $ tar xzvf opus-1.3.1.tar.gz
    $ cd opus-1.3.1

Build and install:

    $ ./configure --prefix=/path/to/Telephone/ThirdParty/Opus --disable-shared CFLAGS='-arch arm64 -arch x86_64 -Os -mmacosx-version-min=15.6'
    $ make
    $ make install

### LibreSSL

Download:

    $ curl -O https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.1.5.tar.gz
    $ curl -O https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.1.5.tar.gz.asc
    $ gpg --verify libressl-3.1.5.tar.gz.asc
    $ tar xzvf libressl-3.1.5.tar.gz
    $ cd libressl-3.1.5

Build and install:

    $ ./configure --prefix=/path/to/Telephone/ThirdParty/LibreSSL --disable-shared CFLAGS='-arch arm64 -arch x86_64 -Os -mmacosx-version-min=15.6'
    $ make
    $ make install

### PJSIP

Download:

    $ curl -o pjproject-2.10.tar.gz https://codeload.github.com/pjsip/pjproject/tar.gz/2.10
    $ tar xzvf pjproject-2.10.tar.gz
    $ cd pjproject-2.10

Create `pjlib/include/pj/config_site.h`:

    #define PJSIP_DONT_SWITCH_TO_TCP 1
    #define PJSUA_MAX_ACC 32
    #define PJMEDIA_RTP_PT_TELEPHONE_EVENTS 101
    #define PJ_DNS_MAX_IP_IN_A_REC 32
    #define PJ_DNS_SRV_MAX_ADDR 32
    #define PJSIP_MAX_RESOLVED_ADDRESSES 32
    #define PJ_HAS_IPV6 1

Patch:

    $ patch -p0 -i /path/to/Telephone/ThirdParty/PJSIP/patches/sock_qos_darwin.patch
    $ patch -p0 -i /path/to/Telephone/ThirdParty/PJSIP/patches/os_core_unix.patch
    $ patch -p0 -i /path/to/Telephone/ThirdParty/PJSIP/patches/coreaudio_dev.patch

Build and install (remove `--with-opus` option if you don’t need Opus):

    $ ./configure --prefix=/path/to/Telephone/ThirdParty/PJSIP --with-opus=/path/to/Telephone/ThirdParty/Opus --with-ssl=/path/to/Telephone/ThirdParty/LibreSSL --disable-video --disable-libyuv --disable-libwebrtc --host=arm-apple-darwin CFLAGS='-arch arm64 -arch x86_64 -Os -DNDEBUG -mmacosx-version-min=15.6' CXXFLAGS='-arch arm64 -arch x86_64 -Os -DNDEBUG -mmacosx-version-min=15.6'
    $ make lib
    $ make install

    
Build Telephone.

## Contribution

For the legal reasons, pull requests are not accepted. Please feel
free to share your thoughts and ideas by commenting on the issues.
