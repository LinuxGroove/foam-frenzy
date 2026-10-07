#!/bin/sh
# Prints this checkout's version, for builds and for runs from source.
#
# Releases are tagged vYYYY.WW.MINOR: the year and week of the release, then
# a number that starts at 0 for each week's first release. Weeks run Sunday
# to Saturday (UTC) and are numbered like ISO weeks: a Sunday belongs to the
# ISO week of the Monday after it. A build of a
# tagged commit is that version without the v (2026.41.0); any other commit
# adds how many commits it is past the last release and its hash
# (2026.41.0+3.g1a2b3c4d), like git describe. Before the first release tag,
# the base is the commit's own week.
#
#   tools/version.sh             # print it
#   tools/version.sh --stamp     # also write it to project.godot
set -eu
cd "$(dirname "$0")/.."

if d=$(git describe --tags --long --abbrev=8 --match 'v[0-9][0-9][0-9][0-9].*' 2>/dev/null); then
	tag=${d%-*-g*}
	rest=${d#"$tag"-}
	count=${rest%%-*}
	hash=${rest#*-g}
	base=${tag#v}
else
	when=$(git log -1 --format=%ct 2>/dev/null || date +%s)
	# A day later, so Sunday counts as the start of the next ISO week.
	when=$((when + 86400))
	week=$(date -u -d "@$when" +%V | sed 's/^0//')
	base="$(date -u -d "@$when" +%G).$week.0"
	count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
	hash=$(git rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
fi

if [ "$count" = 0 ] && [ "${tag:-}" != "" ]; then
	version=$base
else
	version="$base+$count.g$hash"
fi

if [ "${1:-}" = "--stamp" ]; then
	sed -i "s/^config\/version=\".*\"$/config\/version=\"$version\"/" project.godot
	grep -q "^config/version=\"$version\"$" project.godot
fi
echo "$version"
