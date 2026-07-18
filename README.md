# FocusGuard

[![CI](https://github.com/simonleandergrimm/FocusGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/simonleandergrimm/FocusGuard/actions/workflows/ci.yml)

FocusGuard is a native macOS commitment blocker. Describe a focus session in ordinary language—or set it up manually—review the exact plan, and activate it.

<img width="932" height="570" alt="image" src="https://github.com/user-attachments/assets/971d5f8f-6921-4c98-ad22-43ed89361a68" />


> [!IMPORTANT]
> Note—it was fully coded by AI. Proceed with caution. By now, I fully back up my laptop, and I know how to kill applications through terminal, so I'm fine with the amount of access. But no guarantee this won't brick your machine!

## What it does

- Blocks websites and installed macOS applications for one-time or recurring sessions.
- Turns requests such as “Block Hacker News and Slack for two hours, locked” into a reviewable structured plan using the OpenAI Responses API.
- Also supports fully manual setup, which does not require an API key.
- Offers Flexible, Focused, and Locked modes with progressively longer early-exit delays.
- Keeps enforcing active plans after the main app closes and across restarts.
- Includes an optional local Chromium extension that replaces blocked HTTPS pages with a reminder page.

## Requirements

- macOS 14 Sonoma or newer
- Apple command-line developer tools (`xcode-select --install`)
- An administrator account for the one-time helper installation
- Optional: an [OpenAI API key](https://platform.openai.com/api-keys) for natural-language planning

## Install from source

```sh
git clone https://github.com/simonleandergrimm/FocusGuard.git
cd FocusGuard
./Scripts/install-app.sh
```

The script builds an ad-hoc signed app on your Mac, installs it at `/Applications/FocusGuard.app`, and opens it. Building locally avoids asking users to bypass Gatekeeper for an unsigned downloaded binary.

On first launch:

1. Approve the macOS administrator dialog for the background helper.
2. To use natural-language planning, open **FocusGuard → Settings** and save a newly created OpenAI project API key.
3. Enter a request, review the sites, apps, schedule, and strictness, then activate it.

You can instead choose **Manual** to create blocks without OpenAI.

## How enforcement works

A root-owned launchd helper:

- adds website blocks inside `# BEGIN FOCUSGUARD MANAGED BLOCK` and `# END FOCUSGUARD MANAGED BLOCK` in `/etc/hosts`;
- listens only on `127.0.0.1` to show a local reminder page and answer extension health checks;
- closes selected applications while a plan is active;
- reads the policy stored at `~/Library/Application Support/FocusGuard/policy.json`; and
- starts at boot and is restarted by launchd if it exits.

FocusGuard registers the main app as a login item on first launch so it can show status and recurring-block warnings. This can be disabled in Settings.

FocusGuard assumes a single-user Mac: the helper is installed for the account that ran the setup (its user ID is fixed at install time), and only that account's applications are closed. Website blocks in `/etc/hosts` affect every account on the machine.

## Privacy and API use

- Manual blocks remain entirely local.
- For natural-language planning, FocusGuard sends the text of the request to `https://api.openai.com/v1/responses` and asks for a fixed JSON schema. The model never controls the helper directly.
- The API key is stored in the current macOS user's Keychain. Existing development installs automatically migrate a key previously stored in preferences.
- The default model is `gpt-5.6-terra` with medium reasoning and can be changed in Settings.
- The browser extension sends navigation hostnames only to the local helper at `127.0.0.1`; it does not transmit page contents or browsing data.
- FocusGuard contains no analytics or developer-operated backend.

API usage is billed to the key's OpenAI project. Set project limits in the OpenAI dashboard if desired. Never commit a key or paste it into a chat; revoke any exposed key before using FocusGuard.

## Strictness

- **Flexible:** end the plan immediately.
- **Focused:** ending starts a 90-second cooling-off period.
- **Locked:** emergency unlock requires confirmation and a persistent 10-minute cooling-off period.

For recurring schedules, an emergency unlock ends only the active occurrence; the next occurrence remains scheduled.

## Browser landing pages

Plain HTTP blocks reach the helper's reminder page directly. HTTPS authenticates the destination before loading a page, so an optional Chromium extension performs the local redirect without installing an interception certificate.

In FocusGuard Settings, select **Export and show extension**. Then open the extensions page in Chrome, Brave, Edge, or another Chromium browser, enable Developer mode, choose **Load unpacked**, and select the folder FocusGuard opened.

Website blocking still works without the extension; the browser will show its normal connection error for blocked HTTPS sites.

**Secure DNS bypasses hosts-file blocking.** Browsers with Secure DNS / DNS over HTTPS enabled (Chrome's "Use secure DNS", Firefox's DoH) resolve names remotely and ignore `/etc/hosts`, which silently defeats website blocks in that browser. Install the extension (which does not depend on DNS) or turn off Secure DNS in the browser's settings. Application blocking is unaffected.

## Development

Run the tests:

```sh
swift test
node Scripts/test-browser-extension.js
```

Build the application bundle without installing it:

```sh
./Scripts/build-app.sh
open dist/FocusGuard.app
```

The build script places Swift and Clang caches inside `.build`, so normal builds do not depend on writable global cache directories. Rebuilding the app does not replace a previously installed privileged helper; use the **Update** action in FocusGuard after helper changes.

For security issues, see [SECURITY.md](SECURITY.md).

## Uninstall

From a source checkout, first remove the helper and FocusGuard's managed hosts entries:

```sh
sudo ./Scripts/uninstall-helper.sh
```

Then move `/Applications/FocusGuard.app` to the Trash. User preferences and saved schedules remain in `~/Library/Application Support/FocusGuard` unless you remove that folder separately.

## License

FocusGuard is available under the [MIT License](LICENSE).
