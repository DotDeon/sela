#!/bin/zsh
source ~/.zshrc >/dev/null 2>&1
K=/Users/deon/.claude/skills/scroll-craft/scripts/kie.mjs
node $K shot "The camera pushes slowly and steadily forward toward the dark stone at water level, a smooth continuous dolly-in. The river keeps flowing around the stone in silky streaks and the mist drifts slowly to the right. The stone stays perfectly still and centred in frame throughout. One single continuous take, no cuts, no camera shake, no zoom snap. Slow, cinematic, controlled." out/hero.png out/hero.mp4 --dur 5 > out/hero-clip.log 2>&1 && echo "hero clip done" || echo "hero clip FAILED" &
node $K shot "The camera stays perfectly still, locked off, looking straight down at the river. Only the water moves, flowing steadily and smoothly from the top-left corner toward the bottom-right corner in silky streaks. The dark rock on the left edge does not move. One single continuous take, no cuts, no camera movement, no zoom. Calm, cinematic, controlled." out/river.png out/river.mp4 --dur 5 > out/river-clip.log 2>&1 && echo "river clip done" || echo "river clip FAILED" &
wait
