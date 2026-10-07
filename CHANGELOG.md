# Changelog

All notable changes to this project will be documented in this file.

## [1.2.3] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.2.2] - 2026-10-01

### Fixed
- The downloadable zip is published again. `dist/galaxies.zip` had never been
  committed since galaxies stopped being a set-aside plugin: `dist/` is
  gitignored, so a newly built zip is invisible to `git add dist/` and the
  monorepo release workflow kept skipping the plugin for want of one. Plugin
  Manager was unaffected -- it fetches individual files, not the zip.

## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

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
