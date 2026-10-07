# Vendored: Nakama Godot client

- Upstream: https://github.com/heroiclabs/nakama-godot
- Commit: 6dc7b3951d98cc3807cafb3f1dbc9b44d9b98d21 (master, 2026-09-22)
- License: Apache-2.0 (see LICENSE)

Copied from `addons/com.heroiclabs.nakama`, minus the Satori SDK and the
C# (`dotnet-utils`) adapters, which Foam Frenzy doesn't use. To update, copy the
same folders from a newer upstream commit and update the hash above.

## Local changes

- `utils/NakamaMultiplayerPeer.gd`: implements `_disconnect_peer` (the peer is
  reported gone and its packets are dropped until it joins again, since a
  relayed match can't remove anyone) and `_close`. Upstream leaves both
  unimplemented, so kicks did nothing and closing logged errors. Re-apply
  after updating.
