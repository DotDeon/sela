#!/bin/zsh
source ~/.zshrc >/dev/null 2>&1
K=/Users/deon/.claude/skills/scroll-craft/scripts/kie.mjs
P=$(cat preamble.txt)
still() { node $K still "$P

$2" out/$1.png --ar $3 > out/$1.log 2>&1 && echo "$1 done" || echo "$1 FAILED"; }
still hero "A single large smooth dark basalt boulder sits in the exact centre of a fast mountain river, the water parting around it in long silky white streaks. Mist hangs low over the water. Dark pine forest and faint mountains dissolve into fog in the far distance. Camera at water level a few metres from the stone, slightly low angle. The top of the stone is dry and catches a faint warm rim light. Generous dark negative space in the lower third and the left third." 16:9 &
still river "Top-down aerial view looking straight down at a wide dark river. Long silky streaks of white water flow diagonally from the top-left corner to the bottom-right corner across the whole frame, over dark submerged stones. Calm darker pools near the left edge. No horizon, no sky, no banks except a sliver of dark rock along the left edge. Even and uncluttered, a texture of flowing water." 16:9 &
still clear "Looking straight down through perfectly clear, still, shallow mountain water at smooth rounded pebbles in slate, teal and charcoal tones, every stone crisp and sharp. Gentle caustic light patterns ripple across the stones. Glassy calm surface. The frame is filled edge to edge with pebbles." 16:9 &
still close "A smooth dark basalt boulder stands in a perfectly still, mirror-flat mountain lake at night just before dawn, its reflection exact beneath it. Deep blue sky with a few faint last stars, a thin band of warm light low on the horizon behind distant black mountains. The stone sits in the lower centre of the frame. Large calm empty sky above for text." 16:9 &
wait
