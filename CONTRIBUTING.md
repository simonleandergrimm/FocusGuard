# Contributing to FocusGuard

Thanks for helping improve FocusGuard.

## Development setup

FocusGuard requires macOS 14 or newer and Swift 6 through the Apple command-line developer tools or Xcode.

Before opening a pull request, run:

```sh
swift test
node Scripts/test-browser-extension.js
./Scripts/build-app.sh
```

Please keep changes focused, add or update tests for enforcement behavior, and explain any change to the privileged helper or `/etc/hosts` handling in the pull request.

## Safety

Do not include API keys, policy files, logs containing personal application names, or other local data in issues or pull requests. Report vulnerabilities according to [SECURITY.md](SECURITY.md).
