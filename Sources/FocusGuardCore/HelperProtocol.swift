import Foundation

/// Increment only when the privileged helper's behavior or launch configuration changes.
/// App-only UI and model changes deliberately do not require a helper reinstall.
public enum FocusGuardHelperProtocol {
    public static let currentVersion = 10
}
