# Foam Frenzy

Foam darts, pillow forts and up to eight friends. Every dart you fire is a
dart someone else can pick up.

A top-down foam dart party game for 2 to 8 players, built with Godot 4 for
Ubuntu. Design: [idea 10](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/10-foam-frenzy.md)
in game-ideas.

## How a match plays

- Everyone starts with a handful of darts. Darts you fire land on the floor,
  where anyone can scoop them up, so ammo is the whole game.
- Three hits and you're out for a few seconds. You come back with a short
  shield that drops the moment you fire.
- **Dive** to dodge: you can't be hit mid-dive.
- Pick a blaster in the lobby: Pocket Pistol, Triple Tap, Foam Cannon or Dart
  Hose. They trade accuracy, spread and how fast they eat darts.

Modes:

| Mode | Goal |
|---|---|
| Free-for-all | Most tags wins |
| Team Battle | Red against Blue, most tags wins |
| Capture the Flag | Bring the other team's flag home while yours is safe |
| Dart Hoarder | Hold the most darts when the buzzer goes |

Arenas: **The Gym** (columns, crates and statues) and **The Test Lab** (two
labs and a hall joined by sliding doors on a timer).

## Playing

- **Play with bots**: a match on this device, with bots filling the spots.
- **Host / Join on this network**: hosts are found automatically, or join with
  the host's code.
- **Play online**: through a [LinuxGroove game server](https://github.com/LinuxGroove/game-server).
- **Practice round**: a short guided warm-up against two coaches.
- **On one screen**: in the lobby, press Start on another controller to add a
  player. Up to four players can share a screen, and couch players can also
  join a LAN or online game together.

Controls (controller first, keyboard and mouse always work):

| Action | Controller | Keyboard and mouse |
|---|---|---|
| Move | Left stick | WASD |
| Aim | Right stick | Mouse, or arrow keys |
| Fire | RT or RB | Left click |
| Dive | A, LT or LB | Space, Shift or right click |
| Taunt | Y | E |
| Scoreboard (hold) | View / Back | Tab |
| Pause | Menu / Start | Esc |

Menus work with the d-pad: left and right move between panels, A starts
editing a setting, left and right change it, A or B finishes. Text fields
open an on-screen keyboard that never covers the field.

## Building and testing

You need Godot 4.7.

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn            # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=5   # unit tests and whole bot matches
godot --path . -- --solo --mode=ctf --arena=lab               # straight into a match with bots
godot --path . -- --practice                                  # straight into the practice round
```

`tools/screenshot.tscn` saves screenshots of menus and matches without a
screen (run it under `xvfb-run`; options are listed at the top of
`tools/screenshot.gd`).

## Snap

`snapcraft pack` builds a strictly confined snap, `foam-frenzy`, with the
exported game. It is a regular desktop snap with the gnome extension, so it
runs the same on an Ubuntu desktop and on a handheld's gamepad shell. See
[docs/packaging.md](docs/packaging.md).

Two workflows run on GitHub: **CI** (`.github/workflows/ci.yml`) checks every
script and runs the tests; **Snap** (`.github/workflows/snap.yml`) builds the
snap for amd64 and arm64 and publishes to the candidate channel when a release
is published.

## Layout

| Path | What |
|---|---|
| `game/` | Foam Frenzy itself: match rules and host, bots, arenas, actors, UI, sessions |
| `addons/linuxgroove/` | The shared LinuxGroove add-on (settings, input, seats and glyphs, theme, screen fitting, LAN, online). Kept self-contained so it can move to its own repository |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client |
| `assets/kenney/` | Kenney packs (CC0) |
| `tests/`, `tools/` | Test runner, script checker, screenshot and simulation tools |
| `snap/` | Snap packaging |

Code is MIT (see `LICENSE`); assets and other credits in [CREDITS.md](CREDITS.md).
