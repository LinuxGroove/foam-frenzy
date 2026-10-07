class_name LGNameMaker
extends RefCounted
## Makes player-style names for bots, like "MossyOtter" or "QuietFern42":
## unique within a game, at most `max_length` letters, and friendly. Games
## can pass their own word lists for a themed feel.
##
##   var name := LGNameMaker.make(used_names)

const ADJECTIVES := [
	"Brave", "Breezy", "Cheeky", "Clever", "Cosmic", "Crispy", "Daring", "Dizzy",
	"Fuzzy", "Gentle", "Golden", "Happy", "Hidden", "Humble", "Jolly", "Lucky",
	"Mellow", "Merry", "Misty", "Mossy", "Nimble", "Plucky", "Proud", "Quiet",
	"Rowdy", "Rusty", "Shy", "Silver", "Sleepy", "Sly", "Snowy", "Stormy",
	"Sunny", "Swift", "Tiny", "Wild", "Witty", "Zesty",
]
const NOUNS := [
	"Acorn", "Badger", "Beetle", "Biscuit", "Bramble", "Clover", "Comet", "Crumpet",
	"Falcon", "Fern", "Ferret", "Fox", "Gecko", "Heron", "Kettle", "Lantern",
	"Llama", "Marmot", "Mole", "Moth", "Muffin", "Newt", "Noodle", "Otter",
	"Pebble", "Pickle", "Puffin", "Pumpkin", "Raven", "Rocket", "Sparrow", "Squid",
	"Thistle", "Toad", "Turnip", "Waffle", "Walrus", "Wombat", "Yeti",
]


## A name not in `used` (compared ignoring case).
static func make(used: Array = [], rng: RandomNumberGenerator = null, max_length := 16,
		adjectives: Array = ADJECTIVES, nouns: Array = NOUNS) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var taken := {}
	for n in used:
		taken[str(n).to_lower()] = true
	for attempt in 64:
		var name := "%s%s" % [adjectives[rng.randi() % adjectives.size()], nouns[rng.randi() % nouns.size()]]
		# Some players add a number; so do some bots, and it helps when the
		# plain combinations are taken.
		if rng.randf() < 0.3 or attempt >= 32:
			name += str(rng.randi_range(2, 99))
		if name.length() <= max_length and not taken.has(name.to_lower()):
			return name
	var i := 1
	while taken.has(("Player%d" % i).to_lower()):
		i += 1
	return "Player%d" % i
