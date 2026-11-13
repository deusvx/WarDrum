# Tests

War Drum can't be tried out in a fight on demand, so these run it outside the
game, against a tiny stand-in for it (`fakegame.lua`).

```
pip install lupa
tests/run_tests.sh
```

Each file in `scenarios/` is one situation, told in order: who is around, what
the game reports, what the list must show afterwards. Every scenario starts
from scratch.

The stand-in is strict about one thing the real game is strict about: values the
game hides during a fight (`SECRET`). Comparing, printing or joining one is an
error here too, so a scenario that hands the addon hidden names or levels proves
it never touches them.

`python tests/mutate.py` checks the tests themselves: it breaks one rule at a
time in a copy of the addon (duels count, the same fight is counted twice, a
corpse sets off the warning, ...) and reports whether the scenarios noticed.

`extras/render/render.py` draws the list and the options window from the addon's
own code (needs `pip install pillow`), to look at the layout without the game.
The fonts and the icon are stand-ins, so it is a layout check, not a screenshot.

What none of this can tell: whether the real game behaves the way the stand-in
does. The facts it is built on (what the damage meter returns after a fight,
two-part names, what is readable about an enemy player) were read from the real
client with the addon's own recorder (`/wd dump`, then look at `WarDrumDB.log`
in the saved variables).
