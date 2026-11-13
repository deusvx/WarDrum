# Changelog

## 0.9.1 (beta)
From the first real fights.

- **Fights you started:** recognised by your own first move (a harmful spell, Auto Shot, a swing or
  your pet's attack) at a player who was not targeting you. Before, a player you jumped could still
  be listed for fighting back.
- **Your kills:** counted the moment a listed player you are fighting dies, also late in a long
  fight, and counted again when a soulstone brings them back and you kill them a second time.
- The record now notes your first move, each death it sees and each honor gain.

## 0.9.0 (beta)
First version meant for others to try.

**The list**
- Enemy players who attack you, newest first: name in class color, level, class, kills.
- Slim by default (200 wide, down to 160), level and class columns can be switched off.
- A row lights up red while that player is near; the list's top line brightens with it.
- Grows downwards from its top-left corner and stays put when its size changes.
- Drag it by the title or by a row; lock it in place; scroll with the mouse wheel, with a small
  gold marker showing where you are.
- Tooltip: attacks, kills, your kills, when and where you last met.

**Who gets listed**
- Shown at once when an enemy player has you targeted in a fight; settled after the fight from
  the game's damage meter: whoever damaged you stays (seen or not), whoever didn't comes off.
- Die, and everyone who damaged you in that fight gets the kill. If the meter can't be read at
  that moment, the kill goes to whoever was on you and is put right when the fight ends.
- Never listed: your own faction (duels), battlegrounds and arenas (a switch), players you
  attacked first, pets and creatures.
- A death outside a fight is nobody's kill.

**The warning**
- A chat line and a war drum when a listed player comes into view, at most once a minute each.
- Choose the war drum, the game's raid warning, or no sound.

**Options and commands**
- An options window in the style of YaHT Forever's, with a preview and a help panel.
- `/wd` (the settings), `/wd show`, `/wd hide`, `/wd demo` (sample players), `/wd remove Name`, `/wd clear`, `/wd reset`.
- The game's addon menu by the minimap: click for the list, right-click for the settings.
