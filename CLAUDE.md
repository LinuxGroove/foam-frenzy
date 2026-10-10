# Foam Frenzy

A twin-stick party arena shooter for 1–8 players, with couch play (up to four on one screen) that also joins LAN and online games, in Godot 4.7 with GDScript. The concept is idea 10 in [game-ideas](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/10-foam-frenzy.md). Online play goes through the shared [game server](https://github.com/LinuxGroove/game-server); **read game-ideas' [online-addon.md](https://github.com/LinuxGroove/game-ideas/blob/main/online-addon.md) before touching networking, online or the shared add-on.**

## Commands

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn                  # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=5         # unit tests and whole bot matches
godot --path . -- --solo --mode=ctf --arena=lab                     # straight into a match with bots
godot --path . -- --practice                                        # straight into the practice round
godot --headless --path . tools/net_check.tscn -- host /tmp/code [lan] &   # two copies play a match
godot --headless --path . tools/net_check.tscn -- join /tmp/code [lan]
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots [group=lobby]
```

The screenshot run needs a Vulkan driver to look like the game (Mesa's lavapipe works without a GPU: `apt install mesa-vulkan-drivers`); with only OpenGL the arenas come out paler.

Run the script check and the tests before every commit. Headless runs reimport assets and rewrite many `*.glb.import` files and `icon.png.import`; revert those (`git checkout -- '*.import'`, `rm icon.png.import`) unless you meant to change them.

## Layout

| Path | What |
|---|---|
| `game/game_config.gd` | `GAME_ID`, `PROTOCOL`, player limits, `MAX_LOCAL`, `QUICK_MATCH_SIZE`, campers, colours, setting defaults, input map |
| `game/net/session.gd` | `Session` autoload: lobby, couch seats and transport for solo, LAN, online rooms and quick match |
| `game/net/online_server.gd` | Default game server; `SERVER_KEY` stays `defaultkey` in git |
| `game/match/` | Rules and modes, `MatchHost` (the authoritative match), bot brains |
| `game/arena/` | Arenas: layouts (The Gym, The Test Lab) in `ArenaGrid.LAYOUTS`, and building them |
| `game/ui/` | Title, lobby, HUD, scoreboard, pause menu, tutorial pages |
| `addons/linuxgroove/` | Shared LinuxGroove add-on (settings, input and seats, theme, screen fitting, LAN, online, names) |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client with a local patch (see its `VENDORED.md`) |
| `tests/run_tests.gd` | Headless test runner; add checks with `check(ok, "what")` |
| `tools/` | Script checker, screenshots (`xvfb-run`), `net_check` two-copy match |
| `docs/screenshots/<group>/` | Every menu, arena, mode and in-match screen, with a README index, made by `tools/screenshot.tscn -- --all=docs/screenshots` |

## How the game is built

- **Host-authoritative.** Peer 1 runs the match (`MatchHost`); bots exist only on the host. Clients send requests (`_c_*` RPCs) and the host sends state (`_h_*`), always with `rpc_id`.
- **Couch seats.** Each device's players are seats of its peer, with actor id `peer * 4 + seat` so ids match on every device. The hello carries all of a device's seats; seat 0 is the signed-in account, and couch guests aren't reported online.
- **One Session for every mode.** Solo, LAN, online rooms and quick match all run the same game code. Follow the rules in online-addon.md: never attach the bridge's peer yourself, never send a second hello, no `await` between joining and setting `mode`.
- **Bump `PROTOCOL`** whenever any RPC's arguments or meaning change.
- **Online results** come from `Session.report_match` (host only, online rooms only, not practice, seat 0 of each device only) to the server's `foam-frenzy.match_report`, which writes stats and the wins and tags boards. Changing what's reported means changing `modules/src/games/foam-frenzy.ts` in game-server too, and deploying the server first.
- **Play tests.** The shared add-on's `LGPlaytest` records a play test when the Play test recording setting is on (or with `-- --playtest`): a picture every few seconds, game events, frame times and controls, the player's notes (F8, or Note this moment in the pause menu) and a survey when they quit, all in one zip in `user://playtest/`. Game events go through `LGPlaytest.event()` and `moment()`; the round's own survey questions (and standard ones to skip) are `GameConfig.PLAYTEST`. Quit through `LGScenes.quit()` so the survey comes first.
- **Everything works offline.** No server, no network and online turned off must all still play.
- **Launch ping.** `game/main.gd` calls `LGLaunchPing.send(GameConfig.GAME_ID)` at startup: one anonymous request to the game server's `/launch` (game, random install id, version, OS, CPU) so the server counts every player, online or not. It's skipped headless, from source and with `DO_NOT_TRACK` set, and never blocks or retries.

## The shared add-on

`addons/linuxgroove/` and `addons/com.heroiclabs.nakama/` are copies shared with [Graveyard Hollow](https://github.com/LinuxGroove/graveyard-hollow) (usually checked out next to this repository). Fix shared behaviour in the add-on, not with a workaround here, keep it game-agnostic, and port the change to Graveyard Hollow in the same piece of work. When the change affects how games should use the add-on, update online-addon.md in game-ideas too. Keep the `_disconnect_peer` and `_close` patch in `NakamaMultiplayerPeer.gd` when updating nakama-godot.

## Style

- Match the surrounding code: `##` doc comments on classes and non-obvious functions, short comments only where the reason isn't obvious.
- Connect signals with methods (or `bind`), not lambdas, as the rest of this game does; a lambda on an autoload signal stays connected after its screen is freed.
- Build UI pieces so tests can drive them without a network or a scene change.
- Player-facing text is plain and short, in the game's words (campers, tags, outs, darts).

## Testing online

Prefer a local game server to `play.linuxgroove.com`, since test runs create real accounts and rooms. online-addon.md describes running one in LXD or Docker and the two-instance tests for joining by code and quick match; `tools/net_check.tscn` plays a whole match between two copies. Device logs live in `~/snap/foam-frenzy/common/.local/share/foam-frenzy/logs/godot.log`.

## Releases

Pushing to `main` builds the snap and publishes it to the `edge` channel; a GitHub release publishes to `candidate`. The **Windows and macOS** workflow (`desktop.yml`) exports both from Linux with the `Windows Desktop` and `macOS` presets (a single `.exe`, and a universal, ad-hoc signed `.app`): pushes to `main` keep the zips as artifacts for 5 days, and releases get them attached. They aren't signed by Microsoft or Apple, and the release notes tell players how to open them. CI injects the server key from the `GAME_SERVER_KEY` secret, so never commit the real key.

Versions are `vYYYY.WW.MINOR`: a release is a GitHub release tagged with the year and week and a number from 0 for that week's releases (`v2026.41.0`, then `v2026.41.1`). Weeks run Sunday to Saturday (UTC), numbered like ISO weeks: a Sunday starts the ISO week of the Monday after it. Make releases with the **Release** workflow (Actions, Release, Run workflow): it refuses commits whose CI hasn't passed, picks the next tag, publishes a release whose notes lead with the Snap Store link and list the changes since the last release (`tools/release.sh`), and starts the snap build that publishes it to `candidate` and the Windows and macOS build that attaches those zips to the release. Commit subjects become the release notes, so write them for players. Nobody edits the version by hand: `tools/version.sh` derives it from git (`2026.41.0` on a tag, `2026.41.0+3.g1a2b3c4d` for the third commit after it), CI stamps it into `project.godot` before building, and runs from source ask the same script (`LGVersion`). The game sends it at sign-in, so the server's dashboard shows which versions are played.
