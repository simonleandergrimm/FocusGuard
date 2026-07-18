# FocusGuard landing-page bridge

This optional local extension redirects blocked HTTPS navigations to the reminder page served by the FocusGuard helper. It also checks already-open tabs locally so a block that starts after a page was loaded still takes effect. The underlying hosts-file block remains active without it.

## Chrome, Brave, Edge, or another Chromium browser

1. Open the browser's extensions page.
2. Enable **Developer mode**.
3. Remove any older FocusGuard entry that points to a different or missing folder.
4. Choose **Load unpacked**.
5. Select the `BrowserExtension` folder opened by FocusGuard Settings.

After FocusGuard updates this folder, use the extension page's **Reload** button if the browser was already open. The current extension checks new navigations, already-open pages, tab switches, and periodically scans open tabs while a block is active.

The extension only receives navigation hostnames and asks `127.0.0.1` whether that hostname is in an active FocusGuard commitment. It does not read page contents or transmit browsing data.
