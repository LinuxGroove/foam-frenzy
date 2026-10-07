class_name LGNetwork
extends RefCounted
## Whether this device is on a network at all (Wi-Fi, cable, USB tethering,
## VPN), so menus can say so instead of trying to connect. It can't tell
## whether the internet or the game server is reachable; LGOnline reports that
## when it tries.

const OFFLINE_TEXT := "You're not connected to a network. Connect to Wi-Fi or plug in a network cable, then try again."

## Interfaces that exist without a real network: loopback, and the bridges
## containers and virtual machines add.
const VIRTUAL_PREFIXES := ["lo", "docker", "br-", "virbr", "lxdbr", "veth", "vnet", "podman", "cni", "flannel"]

## Tests set this to true or false to act as if the network were up or down.
static var forced: Variant = null


static func is_up() -> bool:
	if forced != null:
		return bool(forced)
	return is_up_in(IP.get_local_interfaces())


## The check itself, on a list shaped like IP.get_local_interfaces().
static func is_up_in(interfaces: Array) -> bool:
	for iface in interfaces:
		var name := str(iface.get("name", ""))
		if VIRTUAL_PREFIXES.any(func(p): return name.begins_with(p)):
			continue
		for addr in iface.get("addresses", []):
			if _usable(str(addr)):
				return true
	return false


static func _usable(addr: String) -> bool:
	if addr.contains(":"):
		var a := addr.to_lower()
		return a != "::1" and not a.begins_with("fe80")
	return not addr.begins_with("127.") and not addr.begins_with("169.254.") and addr != "0.0.0.0"
