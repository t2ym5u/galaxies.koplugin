# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-09-30

### Fixed
- The generator produced puzzles that could not be solved. A galaxy's centre
  was restricted to the middle of a cell, which forces every region to be
  odd-sized about its centre in both axes -- and an n x n grid usually cannot
  be tiled that way. Measured on the old code: at n >= 7 **every** board fell
  back to the degenerate "one galaxy covering the whole grid", which is not a
  puzzle; at n = 6 only 8 of 20 were valid, the rest asymmetric or split into
  disconnected pieces.
- Centres now live in doubled coordinates, so they can sit in the middle of a
  cell, on the edge between two, or on the corner between four -- as the puzzle
  has always allowed. The tiling is grown symmetrically and is checked to stay
  connected, and a single cell is always a legal galaxy, so generation cannot
  fail: the 3000-attempt retry loop and its fallback are gone. 20 of 20 valid
  at n = 6, 7 and 8, and instant.

### Note
- Saved games from before this version are discarded on load: their centres are
  recorded in the old coordinate space, so they would be drawn in the wrong
  place and the win check would never pass.
