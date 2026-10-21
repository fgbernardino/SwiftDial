# Shared user directory

Open **Local Contacts → User Directory…** (Option-Command-K). Enter the HTTPS
endpoint in **Directory URL** and click **Save URL**. No URL is configured by
default. Clear the URL and save to disable the directory and remove its cache.
**Refresh** reloads the saved URL. Double-click a contact, or select it and choose
**Call**, to dial through the normal account and dial-plan path.

The endpoint can also be entered in MicroSIP's **Settings → Directory of users**.
Return UTF-8 JSON with `Content-Type: application/json`:

```json
{
  "refresh": 300,
  "items": [
    { "name": "Fernando", "number": "201" },
    { "name": "Ana", "number": "002" }
  ]
}
```

- Map shortname to `name` and ramal to `number`. Both must be strings. Keep leading
  zeros and original numbers; do not apply a dial-plan prefix on the server.
- Return the full snapshot on every request, including `items: []` for an empty
  directory. Names must be nonempty (up to 200 characters); numbers must use
  SwiftDial's supported phone-number characters and be unique after normalization.
  Invalid responses are rejected as a whole, preserving the last good snapshot.
- `refresh` is seconds. Missing or zero means load once per launch/manual refresh.
  SwiftDial bounds positive values to 30–86400 seconds. Failures retry in 300 seconds.
- Extra MicroSIP fields, including `silent`, presence, and starred, are ignored.
  Presence-only responses are not snapshots and are rejected. This feature does
  not implement BLF/presence or XML directories.
- MicroSIP may append a `sequence` query parameter. The server may ignore it;
  SwiftDial does not require it.
- Directory contacts are read-only and cached separately from personal contacts.
  Personal names take priority, then directory names, then system contacts. A URL
  change clears the previous directory cache. Failed refreshes keep the cache.
- Use a trusted HTTPS certificate. Interactive login and custom authentication
  headers are not implemented. The saved URL and directory cache are stored in
  app preferences; do not put a reusable account password in the URL.

Reference: https://www.microsip.org/help (Directory of users).
