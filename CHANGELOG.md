# Changelog

All notable changes to this project will be documented in this file.

## [1.5.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.5.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.5.0] - 2026-11-04

### Changed
- New game and opening the game each build one puzzle instead of two: the
  board used to generate a puzzle on creation that the screen then replaced
  (or that a saved game overwrote). Generation was already fast (under 1 ms
  on a desktop), so this mostly saves work; today's Daily Challenge grid is
  a different one than with 1.4.3.

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Added
- "New game" once the puzzle is solved (or the solution is shown): the
  action bar shows it in place of Clear and Undo, so the next puzzle no
  longer needs the menu.
- The rules now explain how to play: tap a cell to assign it to the next
  galaxy and keep tapping to cycle through them.

### Changed
- Redesigned play screen, in line with the other games: a full-width action
  bar, a larger board that fills the available room, and one frame around
  it. The status line reads "size · Unassigned: n" and wraps in landscape
  instead of being cut off.
- Galaxy centres are drawn as round white discs with a black ring and the
  galaxy number centred inside, instead of black squares with a barely
  readable grey number. They now read on shaded and unshaded cells alike,
  and the number -- which tells you which galaxy a tap assigns next -- is
  sized to fit the disc.
- Title-bar menu in the same order as every other game, with "Reveal"
  renamed "Show solution".
- New README screenshot.

### Fixed
- The board's closing grid line was drawn just past its edge, so the right
  and bottom borders spilled outside the board.

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
