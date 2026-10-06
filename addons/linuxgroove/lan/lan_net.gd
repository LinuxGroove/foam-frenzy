class_name LanNet
extends RefCounted
## ENet helpers for host-authoritative LAN play.

const CHANNELS := 4


static func create_host(port: int, max_clients: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients, CHANNELS)
	if err != OK:
		push_warning("LAN: cannot host on port %d (error %d)" % [port, err])
		return null
	return peer


static func create_client(address: String, port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	if err != OK:
		push_warning("LAN: cannot connect to %s:%d (error %d)" % [address, port, err])
		return null
	return peer


## The device's most likely LAN address (private IPv4), or "" if none.
static func local_address() -> String:
	var best := ""
	var best_rank := 99
	for addr in IP.get_local_addresses():
		if addr.contains(":"):
			continue
		var rank := 99
		if addr.begins_with("192.168."):
			rank = 0
		elif addr.begins_with("10."):
			rank = 1
		elif addr.begins_with("172."):
			var second := addr.split(".")[1].to_int()
			if second >= 16 and second <= 31:
				rank = 2
		elif not addr.begins_with("127.") and not addr.begins_with("169.254."):
			rank = 3
		if rank < best_rank:
			best_rank = rank
			best = addr
	return best
