# Ryddm tower defense

Hex-grid tower defense in 3D (isometric camera, Godot 4.6). Everything reacts to the music.

## Controls
| Input | Action |
|---|---|
| 1 / 2 / 3 | pick a hand card; click a hex to build it (Esc / right-click cancels) |
| 4 | pick the saved card |
| right-click a hand card | freeze it in the saved slot |
| right-click a tower | remove it |
| click your base | set the mobs' rally flag (defaults to the nearest enemy base; with several, pick one) |
| WASD / mouse wheel / Q E | pan / zoom / rotate the camera |
| drag a card onto the SAVED slot | freeze it (works even when you can't afford it) |
| Esc | cancel the card being set, otherwise open the pause menu (Resume / Restart / Deck builder / Level creator / Main menu / Quit) |
| Space | toggle slow-motion (same speed as deploying a card) |
| M | mute music |
| F2 | level editor on/off |
| F3 | hide the debug text |

## Code map
```
main.tscn            the one scene; every system below is a node in it
autoload/            singletons: game_events.gd (event bus), conductor.gd (listens to the music, + slow-mo)
audio/               drum_loop.gd (generated test drum loop)
board/               hex_grid.gd (hex math), level_data.gd (level resource), map_generator.gd (random maps),
                     board.gd (builds the level's 3D visuals), pathing.gd (walking distances)
data/                tower_defs.gd (player cards), mob_defs.gd (player mobs), enemy_defs.gd (enemy units + structures),
                     level_rules.gd / music_settings.gd / level_style.gd / enemy_settings.gd (per-level settings),
                     deck_store.gd (saved deck), team.gd
entities/            tower.gd, enemy.gd, mob.gd (plain data objects)
systems/             game.gd (wires everything), tower_manager.gd, unit_manager.gd, enemy_ai.gd, music_director.gd,
                     territory.gd, player_controller.gd, camera_rig.gd, level_editor.gd
ui/                  hud.gd, card_hand.gd, ap_display.gd, pause_menu.gd, game_over_popup.gd, level_settings_panel.gd
fx/                  effects.gd (event -> particles), mats.gd (material helpers)
shaders/             beat-reactive shaders (level, outlines, particles, territory border)
levels/              saved levels (.tres)
```

## Common changes
- **New card / tower:** add an entry to `data/tower_defs.gd` (kinds are documented there; a new kind needs a case in `systems/tower_manager.gd`).
- **New enemy unit:** add an entry to `TYPES` in `data/enemy_defs.gd` (a new behavior needs a case in `systems/unit_manager.gd`).
- **New level:** press F2 and paint it, or generate one; Save writes `levels/<name>.tres`. Drag a saved level onto the
  Main node's `Level` property to start on it.
- **Level creator (F2, or Pause > Level creator):** the toolbar paints the layout; the tabs on the right set the
  *Enemy deck* (presets, spawn rate, unit mix, enemy building), *Win condition* (survive N seconds / defeat N
  enemies, on top of destroying all bases), *Music* (one track or a DJ playlist that switches on a timer, when a
  base falls, or every N kills) and *Look* (colors and particle amount / speed / size / lifetime).
  Everything is saved inside the level's `.tres` file.
- **Structures on the map (level creator, "Place:" row):** click a hex to put an **enemy** turret / slow tower /
  barracks / command post or a **wild** (neutral) turret / den on it; click again to remove it (right-click removes
  it too). Enemy ones are the enemy's own, so they count toward its caps; wild ones shoot and fight *both* sides.
  Wild dens spawn critters that wander near the den. Definitions: `data/enemy_defs.gd` (`STRUCTURES`) and
  `data/neutral_defs.gd`. The enemy commander also builds slow towers and barracks by itself
  (`Max enemy barracks` in the Enemy tab).
- **Tuning:** most numbers are `@export`s: select a node in `main.tscn` and use the inspector.

## Levels and the playlist
- Levels are `.tres` files in `levels/`; their play order is `levels/playlist.json`.
- The first time the folder is empty, a **debug playlist** of 4 generated levels (tutorial, easy, normal, hard, each with
  a different win condition) is created so there is always something to play.
- The start menu: **Play playlist** (in order), **Choose a level**, **Edit playlist** (add / remove / reorder, saved
  automatically), **Level creator**. Levels you save in the creator are appended to the playlist automatically.
- Winning a playlist level offers **Next level**; losing offers **Restart level**; both offer **Main menu**.

## Quick shuffle and spell cards
- The **SHUFFLE** button sits right after the three hand cards. It throws the whole hand away and deals a new one,
  then recharges for 30 seconds of game time (`PlayerController.shuffle_cooldown`).
- **Spell cards** (`"kind": "spell"` in `data/tower_defs.gd`) cost AP like towers but need no target: click one (or
  drop it on the board) and it goes off, and that copy is **gone for the rest of the run**. A deck can hold 2 spell
  cards on top of its normal card limit (`DeckStore.spell_limit`). Spells so far: **Summon** (3-5 mobs appear at
  random spawn points: your base and your barracks / camps) and **Haste** (2-3 random mobs of yours run 2x faster
  for 8 seconds; not spent if you have no mobs out).

## Deck
- Build your deck from the **main menu** or the **pause menu** (Deck builder). It holds at most **4 cards** to start
  with (copies count); the limit is `DeckStore.limit` in `data/deck_store.gd` and can be raised later.
- **Save deck** stores it in `user://deck.json` and it loads automatically next run. **Starter deck** resets to
  Pulse, Rapid, Farm and Barracks.
