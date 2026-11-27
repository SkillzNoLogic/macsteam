// The game list the injected OnlineFix dylib routes through AppID 480.
//
// The manager's games.json is the list of My Games; not every game in it should
// be remapped. A game whose multiplayer runs on Steam's own networking (SDR
// relay, as RV There Yet? does) never gets past "connecting to Steam relay
// servers" while the game's Steam pipe carries Spacewar's AppID 480, so it has
// to reach the client as itself — the same thing the LuaTools fixes do by
// keeping the game's real AppID. That choice stays in this file as the entry's
// keepRealAppID flag: to the dylib, a game missing from here routes as 480.
//
// A game whose recorded fix files are gone is left out too: Steam puts the game's
// own files back on a verify, update or repair, and starting that game as
// Spacewar without the fix that goes with it is how a game stops launching.
//
// The dylib reads its own JSON (ONLINEFIX_CONFIG), so the routed subset is
// written out next to the manager's file rather than editing theirs.
import Foundation

enum OnlineFixRoutingFile {

    /// Rewrites the routed list from the manager's games.json. Returns true when
    /// the file was written. An unreadable list writes an empty one: routing
    /// nothing is the safe state.
    @discardableResult
    static func writeFromManager() -> Bool {
        let routed = routedGames(from: Paths.onlineFixGamesFile)
        do {
            try Paths.ensureDir(Paths.onlineFixSupportDir)
            let data = try JSONSerialization.data(
                withJSONObject: ["games": routed],
                options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Paths.onlineFixRoutingFile, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The manager's games minus the ones whose fix is no longer on disk. The
    /// entries are copied unchanged so every flag the dylib reads survives,
    /// keepRealAppID included.
    static func routedGames(from file: URL) -> [[String: Any]] {
        guard
            let data = try? Data(contentsOf: file),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let games = root["games"] as? [[String: Any]]
        else { return [] }

        let broken = brokenFixIDs(in: root)

        return games.filter { game in
            guard let id = game["id"] as? Int, id > 0, id != 480 else { return false }
            return !broken.contains(id)
        }
    }

    /// Games with a fix record whose files are missing or no longer the fix's own.
    private static func brokenFixIDs(in root: [String: Any]) -> Set<Int> {
        let fixes = root["fixes"] as? [[String: Any]] ?? []
        var ids: Set<Int> = []
        for fix in fixes {
            guard let id = fix["id"] as? Int else { continue }
            if !fixIsInstalled(fix) { ids.insert(id) }
        }
        return ids
    }

    private static func fixIsInstalled(_ fix: [String: Any]) -> Bool {
        // The overlay renderer (GameOverlayRenderer64.dll) is a compatibility aid a
        // Windows-prefix cleanup takes; it does not make the fix itself missing.
        let files = (fix["files"] as? [String] ?? []).filter {
            ($0 as NSString).lastPathComponent != "GameOverlayRenderer64.dll"
        }
        guard !files.isEmpty else { return false }
        let sizes = fix["sizes"] as? [String: Any] ?? [:]
        let fm = FileManager.default
        for path in files {
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value else { return false }
            // The app rewrites dlllist.txt and a player may tune OnlineFix.ini; only
            // the files that carry the fix itself are compared by size.
            let name = (path as NSString).lastPathComponent.lowercased()
            if name == "dlllist.txt" || name == "onlinefix.ini" || name == "onlinefix.url" {
                continue
            }
            if let recorded = (sizes[path] as? NSNumber)?.int64Value, recorded != size {
                return false
            }
        }
        return true
    }
}
