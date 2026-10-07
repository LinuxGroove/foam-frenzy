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
```

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

## How the game is built

- **Host-authoritative.** Peer 1 runs the match (`MatchHost`); bots exist only on the host. Clients send requests (`_c_*` RPCs) and the host sends state (`_h_*`), always with `rpc_id`.
- **Couch seats.** Each device's players are seats of its peer, with actor id `peer * 4 + seat` so ids match on every device. The hello carries all of a device's seats; seat 0 is the signed-in account, and couch guests aren't reported online.
- **One Session for every mode.** Solo, LAN, online rooms and quick match all run the same game code. Follow the rules in online-addon.md: never attach the bridge's peer yourself, never send a second hello, no `await` between joining and setting `mode`.
- **Bump `PROTOCOL`** whenever any RPC's arguments or meaning change.
- **Online results** come from `Session.report_match` (host only, online rooms only, not practice, seat 0 of each device only) to the server's `foam-frenzy.match_report`, which writes stats and the wins and tags boards. Changing what's reported means changing `modules/src/games/foam-frenzy.ts` in game-server too, and deploying the server first.
- **Everything works offline.** No server, no network and online turned off must all still play.

## The shared add-on

`addons/linuxgroove/` and `addons/com.heroiclabs.nakama/` are copies shared with [Graveyard Hollow](https://github.com/LinuxGroove/graveyard-hollow) (usually checked out next to this repository). Fix shared behaviour in the add-on, not with a workaround here, keep it game-agnostic, and port the change to Graveyard Hollow in the same piece of work. When the change affects how games should use the add-on, update online-addon.md in game-ideas too. Keep the `_disconnect_peer` and `_close` patch in `NakamaMultiplayerPeer.gd` when updating nakama-godot.

## Style

- Match the surrounding code: `##` doc comments on classes and non-obvious functions, short comments only where the reason isn't obvious.
- Connect signals with methods (or `bind`), not lambdas, as the rest of this game does; a lambda on an autoload signal stays connected after its screen is freed.
- Build UI pieces so tests can drive them without a network or a scene change.
- Player-facing text is plain and short, in the game's words (campers, tags, outs, darts).

## Testing online

Prefer a local game server to `play.linuxgroove.com`, since test runs create real accounts and rooms. online-addon.md describes running one in LXD or Docker and the two-instance tests for joining by code and quick match; `tools/net_check.tscn` plays a whole match between two copies. Device logs live in `~/snap/foam-frenzy/current/.local/share/foam-frenzy/logs/godot.log`.

## Releases

Pushing to `main` builds the snap and publishes it to the `edge` channel; a GitHub release publishes to `candidate`. CI injects the server key from the `GAME_SERVER_KEY` secret, so never commit the real key. Bump `application/config/version` in `project.godot` for releases.
