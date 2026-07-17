# FocusGuard landing-page bridge

This optional local extension redirects blocked HTTPS navigations to the reminder page served by the FocusGuard helper. It also checks already-open tabs locally so a block that starts after a page was loaded still takes effect. The underlying hosts-file block remains active without it.

## Chrome, Brave, Edge, or another Chromium browser

1. Open the browser's extensions page.
2. Enable **Developer mode**.
3. Choose **Load unpacked**.
4. Select this `BrowserExtension` folder.

The extension only receives navigation hostnames and asks `127.0.0.1` whether that hostname is in an active FocusGuard commitment. It does not read page contents or transmit browsing data.
