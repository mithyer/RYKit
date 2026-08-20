import UIKit

/// Minimal application host used to execute RYKitTests as hosted tests on a device.
@main
final class RYKitTestHostAppDelegate: UIResponder, UIApplicationDelegate {
    /// Completes host application startup without presenting a user interface.
    /// - Parameters:
    ///   - application: The host application instance.
    ///   - launchOptions: Options supplied for the launch event.
    /// - Returns: `true` when the test host may continue launching.
    // TEST:RYKitEncryptionTests[test_keychainEncryptor_canLoadOrCreateKey]
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
