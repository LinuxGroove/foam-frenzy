class_name JoinCode
extends RefCounted
## Short, typeable codes for a host's LAN address, for networks that block
## discovery broadcasts (hotel, campus and guest Wi-Fi).
##
## Common private ranges get short codes: 192.168.x.y on the default port is
## 5 characters. Codes are base 30 with no look-alike pairs: the Kenney fonts
## draw 0 and O, 1 and I, 2 and Z, 5 and S, 8 and B the same, so each pair is
## one symbol and either spelling is read the same way. Case doesn't matter.

const ALPHABET := "0123456789ACDEFGHJKMNPQRTUVWXY"
const LOOK_ALIKES := {"O": "0", "I": "1", "L": "1", "Z": "2", "S": "5", "B": "8"}
## Code length for each payload size in bytes (3 to 7): the fewest base-30
## digits that hold that many bits. Every size has a different length.
const LENGTHS := {3: 5, 4: 7, 5: 9, 6: 10, 7: 12}


static func encode(ip: String, port: int, default_port: int) -> String:
	var octets := ip.split(".")
	if octets.size() != 4:
		return ""
	var b: Array[int] = []
	for o in octets:
		b.append(o.to_int())
	var bytes := PackedByteArray()
	var custom_port := port != default_port
	# Header nibble: 0 = 192.168.x.y, 1 = 10.x.y.z, 2 = 172.16-31.x.y, 3 = any.
	if b[0] == 192 and b[1] == 168:
		bytes = PackedByteArray([0 | (int(custom_port) << 2), b[2], b[3]])
	elif b[0] == 10:
		bytes = PackedByteArray([1 | (int(custom_port) << 2), b[1], b[2], b[3]])
	elif b[0] == 172 and b[1] >= 16 and b[1] <= 31:
		bytes = PackedByteArray([2 | (int(custom_port) << 2) | ((b[1] - 16) << 3), b[2], b[3]])
	else:
		bytes = PackedByteArray([3 | (int(custom_port) << 2), b[0], b[1], b[2], b[3]])
	if custom_port:
		bytes.append((port >> 8) & 0xFF)
		bytes.append(port & 0xFF)
	return _to_base30(bytes)


## Returns {"ip": String, "port": int}, or an empty dictionary if invalid.
static func decode(code: String, default_port: int) -> Dictionary:
	for ch in code.to_upper():
		if not (ALPHABET.contains(ch) or LOOK_ALIKES.has(ch) or ch in ["-", " "]):
			return {}
	var clean := normalize(code)
	var bytes := _from_base30(clean)
	if bytes.is_empty():
		return {}
	var header := bytes[0]
	var kind := header & 0x3
	var custom_port := (header >> 2) & 0x1 == 1
	var ip := ""
	var used := 0
	match kind:
		0:
			if bytes.size() < 3:
				return {}
			ip = "192.168.%d.%d" % [bytes[1], bytes[2]]
			used = 3
		1:
			if bytes.size() < 4:
				return {}
			ip = "10.%d.%d.%d" % [bytes[1], bytes[2], bytes[3]]
			used = 4
		2:
			if bytes.size() < 3:
				return {}
			ip = "172.%d.%d.%d" % [16 + ((header >> 3) & 0xF), bytes[1], bytes[2]]
			used = 3
		3:
			if bytes.size() < 5:
				return {}
			ip = "%d.%d.%d.%d" % [bytes[1], bytes[2], bytes[3], bytes[4]]
			used = 5
	var port := default_port
	if custom_port:
		if bytes.size() < used + 2:
			return {}
		port = (bytes[used] << 8) | bytes[used + 1]
		used += 2
	# A typo usually changes the length; only exact codes are accepted.
	if used != bytes.size():
		return {}
	return {"ip": ip, "port": port}


static func normalize(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		if LOOK_ALIKES.has(ch):
			out += LOOK_ALIKES[ch]
		elif ALPHABET.contains(ch):
			out += ch
	return out


## Formats a code in groups of four for display.
static func pretty(code: String) -> String:
	var out := ""
	for i in code.length():
		if i > 0 and i % 4 == 0:
			out += "-"
		out += code[i]
	return out


static func _to_base30(bytes: PackedByteArray) -> String:
	var value := 0
	for byte in bytes:
		value = (value << 8) | byte
	var out := ""
	for i in LENGTHS[bytes.size()]:
		out = ALPHABET[value % 30] + out
		value /= 30
	return out


static func _from_base30(code: String) -> PackedByteArray:
	var size := -1
	for n in LENGTHS:
		if LENGTHS[n] == code.length():
			size = n
	if size < 0:
		return PackedByteArray()
	var value := 0
	for ch in code:
		var v := ALPHABET.find(ch)
		if v < 0:
			return PackedByteArray()
		value = value * 30 + v
	if value >= (1 << (8 * size)):
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(size)
	for i in range(size - 1, -1, -1):
		out[i] = value & 0xFF
		value >>= 8
	return out
