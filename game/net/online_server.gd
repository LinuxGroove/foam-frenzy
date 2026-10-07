class_name OnlineServer
extends RefCounted
## The LinuxGroove game server this build plays online through by default.
## Players can still point the game elsewhere in Settings.
##
## SERVER_KEY stays "defaultkey" in the repository, which suits a local
## game-server Compose setup. The snap workflow replaces it with the
## GAME_SERVER_KEY secret before building (.github/workflows/snap.yml).

const HOST := "play.linuxgroove.com"
const PORT := 443
const SCHEME := "https"
const SERVER_KEY := "defaultkey"
