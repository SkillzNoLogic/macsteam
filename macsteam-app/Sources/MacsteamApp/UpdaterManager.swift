// Sparkle auto-update lifecycle
import AppKit
import Combine
import Sparkle

/// Updates come from the combined macSteam + NotProton feed named by `SUFeedURL` in the
/// app's Info.plist (build.sh writes it). Each update is checked against `SUPublicEDKey`
/// before it is installed, because the app itself is only ad-hoc signed.
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    /// A build without a feed or a key (a `swift run` dev build, or an older build.sh)
    /// cannot update; starting Sparkle there would only show an error.
    let isConfigured: Bool = {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        return !feed.isEmpty && !key.isEmpty
    }()

    var automaticallyChecksForUpdates: Bool {
        get { isConfigured && controller.updater.automaticallyChecksForUpdates }
        set {
            guard isConfigured else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        guard isConfigured else { return }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard isConfigured else {
            let alert = NSAlert()
            alert.messageText = "This build can't update itself"
            alert.informativeText = "It was built without an update feed. Install a macSteam "
                + "release DMG, or rebuild with ./build.sh, to get automatic updates."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
