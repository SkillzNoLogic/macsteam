# macSteam + NotProton (one app)

One app with a **macSteam** app exactly as before (Store, Fixes, Import Apps, Apps, Achievements, Install, Repair Steam, Settings, plus the Hubcap and LuaTools features), a
**NotProton** sidebar group (Status, Prefixes, Prefix Backups), an **OnlineFix** sidebar group
(**My Games**, **Add Games**) with OnlineFix Manager's pages, and a **Cloud Redirect** page built from
CloudRedirect's own macOS app. The NotProton group is where you set up
and edit your CrossOver settings. All groups work as they did in the separate apps.

Pressing **Install** installs NotProton first, then macSteam. Steam ends up with a separate
`notproton.dylib`, `macsteam.dylib`, `onlinefix.dylib` and, when the build ships it,
`cloud_redirect.dylib`, all listed in Steam's injection list, which is the same result as
installing them one after the other by hand. The dylibs themselves are not merged.

Built from: macSteam **0.8.3** (macsteam-dev) + NotProton **1.2.6** + OnlineFix Manager (New Online Fix).

## What you need (one time)

1. A Mac with Apple Silicon, macOS 15 or newer.
2. **Xcode 26** from the App Store. Open it once and accept the licence.
3. **Homebrew** (https://brew.sh), then in Terminal: `brew install cmake`
4. A copy of **NotProton 1.2.6** (the app). If you already use NotProton 1.2.6 from /Applications, you
   are done. Otherwise download `NotProton.zip` for version 1.2.6 from
   https://github.com/NotProtonNot/NotProton/releases . It supplies NotProton's prebuilt parts
   (CrossOver bridge, fonts, helper tools) so you don't have to compile those.

## Build it

In Terminal, go into this folder and run:

    ./build.sh

If the NotProton you have is somewhere else (or a zip): `./build.sh --notproton-app ~/Downloads/NotProton.zip`

The first run takes a while (it downloads and compiles Dobby and Sparkle). The result is
`dist/macSteam.app`. Drag it into **Applications**, then open it.
NotProton remembers where the app lives, so keep it in Applications.

## Using it

- **Install** (macSteam group): installs NotProton (and sets up the CrossOver tool if CrossOver is
  installed and activated), then macSteam. If NotProton can't install, you get a message and the choice to
  install macSteam alone.
- **NotProton group**: Status (CrossOver, Steam folder, update block, install state), Prefixes, Prefix Backups.
- **Uninstall / Repair Steam** (macSteam group): replaces Steam with a clean Valve copy. That removes
  *both* injections. Your prefixes and CrossOver tool in `~/Library/Application Support/notproton` stay.
- Quit and remove the separate NotProton and macSteam apps if you had them, so only one is around.

## Things you should know

- **Not tested by me.** I wrote this on a Linux machine that can't compile Mac apps. The NotProton patch is
  checked to apply cleanly to the real 1.2.6 source, but nothing has been compiled or run. If `./build.sh`
  stops with a compiler error, copy the red text and send it to me; it should be a quick fix.
- **Steam client version.** This macSteam accepts Steam builds 1792618285 and 1794424036. 1794424036 is also NotProton's stable build, so it is the one that suits both. If Steam is on any other build, Install offers to switch it.
- **Automatic updates** come from this repo's own `appcast.xml`, never from plain macSteam's feed.
  `.github/workflows/mirror-upstream.yml` checks Falhoo/macsteam every 6 hours, rebuilds each new release
  with the updater on, signs it (repository secret `SPARKLE_PRIVATE_KEY`) and adds it to the feed.
  To sign a DMG by hand: `./scripts/appcast-add.sh macSteam-X.Y.Z.dmg X.Y.Z <download URL> [notes]`.
  The patch in `patches/` is tied to NotProton 1.2.6 and may need updating for other versions.
- **NotProton's menu-bar items** (Setup, Prefix menus, keyboard shortcuts) aren't in this app. The same
  actions are buttons inside the NotProton pages. Its Refresh and prefix buttons are in a bar at the top of
  each page.

## OnlineFix group

- **My Games** lists the games added for OnlineFix, with the patch button and remove on every row.
- **Add Games** searches Steam's store by name (or takes an AppID) and adds the game straight to that list.
  Adding opens the patch sheet for the game.
- A game with no OnlineFix on online-fix.me still stays in My Games and is still routed as AppID 480;
  only its fix files are missing, and they can be installed later from the patch sheet.
- **Keep real AppID** on a game's patch sheet stops the routing: the game starts as itself instead of
  Spacewar. Turn it on for games whose online play runs on Steam's own networking (SDR relay) — remapped
  to 480 they never get a relay, and multiplayer waits forever ("waiting for other resources before
  starting the steam network relay"), which is what RV There Yet? did. The toggle takes effect on the
  next launch, no reinstall needed.
- macSteam tells those games apart by reading the game's own binaries for the Steam networking entry
  points (`SteamNetworkingSockets`/`SteamNetworkingUtils`), remembered per game folder in
  `steam-networking.json`. The OnlineFix card on the store page then says why Spacewar cannot connect and
  offers a **Keep real AppID** button (and **Use Spacewar instead** to undo it); the same explanation
  appears in the app's patch sheet. Pressing it writes the manager's setting, so restart Steam and launch
  the game again.
- **Fetch fix automatically** finds the game's uploads folder even when the site spells it differently
  (trailing "?", edition words, a subtitle, a year, "The"): it tries the name and its usual variants, then
  similar titles. A same-name match installs straight away; anything less opens a sheet listing the
  candidates with their name-match percentage so you pick the right game.
- The list is the same `games.json` the stand-alone OnlineFix Manager uses
  (`~/Library/Application Support/OnlineFixManager/`), so games added there are already there. The dylib
  is pointed at `routing.json` in that folder instead, which macSteam rewrites from `games.json` minus the
  games set to keep their real AppID.
- OnlineFix runs as its own injected `onlinefix.dylib`, not inside `macsteam.dylib`. macSteam's
  **Install** copies it into Steam, adds it to the injection list and points it at the manager's
  `runtime/` profiles and `routing.json` with `ONLINEFIX_SIG`, `ONLINEFIX_CONFIG` and `ONLINEFIX_LOG`.
  The shipped profiles cover Steam builds 1791918634, 1792618285 and 1794536281; the dylib picks
  the one matching the running client.
- `./build.sh` compiles the OnlineFix sources (`onlinefix/`) as part of the app and runs
  `scripts/build-onlinefix.sh`, which puts `onlinefix.dylib`, `7zz` and the Steam build profiles into the
  app's Resources. There is nothing extra to install.
- The stand-alone OnlineFix Manager's Installation and Logs pages are not in the sidebar.
- **Licences.** macSteam and NotProton use different licences (NotProton is GPL-3.0 plus others).
  Fine for your own use; if you want to share the combined app, check with both authors and the licence
  files that get copied into the app (Contents/Resources/Licenses).

## Cloud Saves page

- The **Cloud Saves** page is macSteam's own: CloudRedirect runtime status with Install, Update and
  Remove, provider choice (local, custom folder, Google Drive, OneDrive, Cloudflare R2, S3-compatible),
  the folder picker for the folder provider, and the configuration folder.
- Providers that need a sign-in or credentials open CloudRedirect's full app in a window of its own
  (**Set Up Google Drive…**, or **Open Cloud Redirect…**), which also has Games, Backups, Cloud Files,
  Migration and the runtime Setup page.
- `./build.sh` runs `scripts/build-cloudredirect.sh`, which builds the native runtime (including
  Dobby) and stages `cloud_redirect.dylib`, `cloud_redirect_cli`, `cloud760_tool` and
  `cloud_redirect_credentials` in the app's `Contents/Resources/runtime`.
- macSteam's **Install** installs CloudRedirect's runtime automatically, using CloudRedirect's own
  installer: it copies `cloud_redirect.dylib` and the credential helper into Steam, adds the dylib to
  the injection list and re-signs Steam, right after macSteam and OnlineFix. The page's own Install
  button does the same, and `MacsteamApp --install-cloud-redirect` runs just that step for scripts.
- macSteam's older snapshot cloud (`cloud.yaml`) is switched off when the CloudRedirect config is
  configured, so the two systems never write the same files.
- Licences: CloudRedirect (MIT) and Dobby (Apache-2.0), copied into `Contents/Resources/Licenses`.

## What was changed

macSteam (this folder): `macsteam-app/Package.swift`, `main.swift`, `AppDelegate.swift`,
`MainViewController.swift`, `SidebarViewController.swift`, `InstallViewController.swift`,
`UpdaterManager.swift`, new `build.sh` (replaces `make_app.sh`). Ignore `Macsteam.xcodeproj` / `project.yml`;
use `build.sh`.

NotProton (`patches/notproton-1.2.6.patch`, applied by `build.sh`): turned from a stand-alone app into a
library, added a small `Embed.swift` for macSteam to use, let its installer share Steam's injection list
with `macsteam.dylib` instead of refusing/overwriting it, and moved its toolbar buttons into the page.

OnlineFix Manager (`New Online Fix`): moved into `onlinefix/` as a Swift package, keeping its sources as
they were except `App.swift`, whose window is replaced by `OnlineFixApp/Embed.swift`. Its routing no
longer lives inside `macsteam.dylib`: `SteamInstaller.swift` deploys the bundled `onlinefix.dylib` and
its build profiles, extends the injection list with it and writes its `ONLINEFIX_*` environment entries.
`build.sh` calls `scripts/build-onlinefix.sh` to put the dylib, 7-Zip and the Steam build profiles into
the app.


CloudRedirect (`vendor/cloudredirect`, upstream `cloudredirect-macos`): its SwiftUI app is now a
library (`CloudRedirectUI`) that macSteam hosts as the **Cloud Redirect** page, so the old
`CloudSavesViewController` is no longer shown. The upstream app keeps working through a thin
`CloudRedirectSwiftApp` executable. `scripts/build-cloudredirect.sh` builds the native runtime
(dylib, CLI helpers, credential helper) and stages it in `Contents/Resources/runtime`;
`SteamInstaller.deployCloudRedirect()` copies the dylib and credential helper into Steam and
`CloudRedirect.configure()` no longer overwrites the provider settings the page writes.
