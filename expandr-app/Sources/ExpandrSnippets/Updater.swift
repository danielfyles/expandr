import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL and public key live in
/// Info.plist (SUFeedURL / SUPublicEDKey). After an update swaps the app bundle
/// in place, we restart the bundled engine so the launchd agent picks up the new
/// binary.
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    @Published var canCheckForUpdates = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually check for updates (the "Check for Updates…" menu item).
    func checkForUpdates() { controller.updater.checkForUpdates() }

    // MARK: - SPUUpdaterDelegate

    /// Restart the engine after the app relaunches into the new version, so the
    /// launchd agent runs the freshly-installed binary rather than the old one.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        EngineService.restart()
    }
}
