# Stud Distance Visualizer

Small Roblox Studio plugin for quickly previewing stud radii while balancing entities, abilities, and interact ranges.

## What It Does

- Adds a `Distance Visualizer` toolbar button in Studio.
- Lets you type a radius in studs.
- Shows a spherical overlay around the current selection.
- Works with `BasePart`, `Model` (uses `PrimaryPart` or first part), and `Attachment`.

## Install

1. Open Roblox Studio.
2. Create or open a local plugin place/project.
3. Paste the contents of [DistanceVisualizer.plugin.lua](/C:/Users/lazyt/.codex/worktrees/b61f/EXILED/tools/StudDistanceVisualizer/DistanceVisualizer.plugin.lua) into a new plugin script.
4. Save it as a local plugin.

## Use

1. Toggle `EXILED Tools -> Distance Visualizer`.
2. Enter the radius you want in studs.
3. Select any object in Studio to preview its spherical range.

## Notes

- This is intentionally simple and non-destructive.
- It does not modify the place.
- It is meant as a balancing reference tool, not final in-game visualization.
