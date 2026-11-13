# War Drum – who ganked you, and a drum that sounds when they come back

<!-- Summary line for the project page (max 256 characters): -->
<!-- A small list of the enemy players who attack you on WoW Forever: name in class color, level, class and how often they killed you. Builds itself from the game's damage meter and sounds a war drum when one of them is near. -->

**Remember who jumped you.** War Drum is a small window for WoW Forever that fills itself with
the enemy players who attack you: name in class color, level, class, and how many times they
have killed you. When one of them walks back into view, a war drum sounds.

No setup. Get attacked, and they are on the list.

**This is a beta (0.9).** It has run cleanly in ordinary play and its rules are tested outside the
game, but it has seen few real ganks so far. If someone is listed who shouldn't be, or an attacker
is missing, please report it on [GitHub](https://github.com/deusvx/WarDrum/issues).

## It builds itself
- **Shows attackers at once:** an enemy player who has you targeted in a fight is on the list
  before the fight is over.
- **Gets it right afterwards:** WoW Forever has no combat log for addons, so War Drum reads the
  game's own damage meter when the fight ends. Whoever damaged you stays, even a rogue you never
  saw. Whoever didn't is taken off again.
- **Counts the kills:** die, and everyone who damaged you in that fight gets the kill. It counts
  your revenge as well.

## The drum when they are near
- A chat line and a **war drum** the moment a listed player comes into view, at most once a
  minute each. Prefer the game's raid warning, or silence? Pick it in the options.
- Their row lights up red for as long as they are around.

## Only real ganks
- **Duels don't count:** your own faction is never listed.
- **Battlegrounds and arenas don't count** (a switch, on by default).
- **Fights you started don't count:** jump someone who was minding their own business and they
  stay off your list, even if they fight back and win.
- Pets and creatures are never listed.

## Small and yours to shape
- **Slim:** 200 wide by default, as narrow as 160. Level and class columns can be switched off.
- **Its own options window** (`/wd`): width, size, background, rows, lock, the warning
  and its sound, with a live preview and a help panel that explains the setting under your mouse.
- **Sample players** (`/wd demo`) let you place and style the list before anyone has attacked you.
- Drag it by the title or a row, scroll it with the mouse wheel, point at a row for the full
  story: attacks, kills, your kills, when and where you last met.

## Commands
- `/wd` opens the settings
- `/wd show` and `/wd hide` show or hide the list
- `/wd demo` shows sample players
- `/wd remove Name` takes one player off (or Shift + right-click their row)
- `/wd clear` empties the list
- `/wd reset` moves the list back to where it started

## Good to know
- **Keep enemy nameplates switched on.** The game only shows an addon the players whose nameplate
  is on screen, or who you target or point at. The warning relies on that.
- A player named only by the damage meter is listed without a level until you see them.
- During a fight the game hides some details. War Drum fills them in as soon as it may.

## Lightweight
One file, no libraries. It sleeps while no enemy player is around.

By the author of **YaHT Forever**.
