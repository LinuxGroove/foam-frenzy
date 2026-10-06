class_name LanBeacon
extends Node
## Finds games on the local network with no server.
##
## A host calls [method start_advertising]; it broadcasts a small JSON beacon
## once a second. Clients call [method start_listening] and receive
## [signal hosts_changed] with every host heard in the last few seconds.
## Beacons carry the game id and version, so other games and mismatched
## builds can be filtered out or shown as "update to play".

signal hosts_changed(hosts: Array)

const INTERVAL := 1.0
const EXPIRY_MS := 4000
const BROADCAST_ADDRESS := "255.255.255.255"

var beacon_port := 24681
var info := {}

var _udp := PacketPeerUDP.new()
var _mode := ""
var _timer := 0.0
var _hosts := {}


## `p_info` should include at least "game", "version", "name" and "port".
func start_advertising(p_info: Dictionary, port := 24681) -> Error:
	stop()
	beacon_port = port
	info = p_info.duplicate()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.set_dest_address(BROADCAST_ADDRESS, beacon_port)
	if err != OK:
		push_warning("LAN: cannot broadcast on port %d (error %d)" % [beacon_port, err])
		return err
	_mode = "advertise"
	_timer = 0.0
	return OK


## Updates fields of the advertised info (player count, state...).
func update_info(fields: Dictionary) -> void:
	for k in fields:
		info[k] = fields[k]


func start_listening(port := 24681) -> Error:
	stop()
	beacon_port = port
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(beacon_port, "*")
	if err != OK:
		push_warning("LAN: cannot listen on port %d (error %d)" % [beacon_port, err])
		return err
	_mode = "listen"
	_hosts.clear()
	return OK


func stop() -> void:
	if _udp:
		_udp.close()
	_mode = ""


func get_hosts() -> Array:
	return _hosts.values()


func _process(delta: float) -> void:
	if _mode == "advertise":
		_timer -= delta
		if _timer <= 0.0:
			_timer = INTERVAL
			_udp.put_packet(JSON.stringify(info).to_utf8_buffer())
	elif _mode == "listen":
		var changed := false
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = parsed
			entry["address"] = ip
			var sig := entry.hash()
			entry["seen"] = Time.get_ticks_msec()
			var key := "%s:%s" % [ip, str(entry.get("port", 0))]
			if not _hosts.has(key) or _hosts[key].get("sig") != sig:
				changed = true
			entry["sig"] = sig
			_hosts[key] = entry
		var now := Time.get_ticks_msec()
		for key in _hosts.keys():
			if now - int(_hosts[key]["seen"]) > EXPIRY_MS:
				_hosts.erase(key)
				changed = true
		if changed:
			hosts_changed.emit(get_hosts())


func _exit_tree() -> void:
	stop()
