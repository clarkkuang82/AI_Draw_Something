import Foundation

public struct AttestConfig: Sendable {
    public let workerBaseURL: URL
    /// When non-nil and built in DEBUG, requests carry an `X-Dev-Bypass`
    /// header containing HMAC-SHA256(secret, keyId). Worker accepts this only
    /// when its own ENV=dev. Use this to test on Simulator / Apple Silicon Mac
    /// where DCAppAttestService.isSupported is false.
    public let devBypassSecret: String?

    public init(workerBaseURL: URL, devBypassSecret: String? = nil) {
        self.workerBaseURL = workerBaseURL
        self.devBypassSecret = devBypassSecret
    }
}
