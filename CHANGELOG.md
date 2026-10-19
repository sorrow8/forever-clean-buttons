# 1.2.4

- The minimap button stays where a minimap button collector (like Leatrix Plus) put it: it was put back on the minimap's edge at every fight.
- Buffs that replace each other are learned more carefully: only a buff your cast put on you anew counts, and a pair must be seen twice. Groups learned by older versions are cleared once, and /fcb forget clears them by hand. A used-up Clearcasting or a cut-short drink no longer ties unrelated buffs together.
- An absorb shield taking a hit (Power Word: Shield, Ice Barrier, Mana Shield) or a buff losing a charge no longer restarts its timer; only your own recast does.
- No Lua error when the game hides who your target is; a cast whose target isn't known no longer counts as cast on you.
- Macros that use an item no longer look for a spell.
- The main switch's help says it only controls the square look; buff timers are their own option.

# 1.2.3

- Minimap button: left-click opens the settings, right-click turns the addon on or off, and a switch in the window hides it. It's made with LibDBIcon, so minimap button collectors (like Leatrix Plus) take it in with its own tooltip.

# 1.2.2

- Fix: swapping seals in combat left the old seal's timer and green frame on its button until it would have run out. Buffs that replace each other (only one seal can be on you) are learned out of combat, once, and from then on casting one ends the others' timers at once, in combat too.

# 1.2.1

- Buff timers show seconds as a bare number ("15" instead of "15s"); minutes, hours and days keep their letter.

# 1.2.0

- A button whose buff is on you gets a green frame.
- Fix: a recast on yourself was not recognised because Forever adds your surname to the cast target ("Adibas Originals"); now it is, so the timer restarts at once in combat.
- When an aura update in combat names a buff you have (the game hides most of them), its timer restarts or ends with it.
- /fcb debug also shows the known buff instances and the last aura update.

# 1.1.2

- Recasting a buff on yourself in combat restarts its timer from the full duration, instead of counting down the old one.
- Buff timers show time the way the game's buff icons do (seconds up to 90 s, minutes up to 90 m, hours up to 36 h, then days; seconds rounded down) and switch to the new second on time, so they no longer show one second more.
- Where the game hides buff data out of combat too (battlegrounds, arenas, keystones) the last known timers stay instead of vanishing.
- A recast of another rank of the same buff updates every button with that buff.
- Timers update often only while seconds are shown and set the text only when it changes.
- Casts with a hidden target no longer risk a Lua error; failed casts are cleaned up.
- A recast aimed at your name with your realm attached ("Name-Realm") is recognised as a recast on yourself; a player with your name from another realm is not you.
- A bar that shows up later (only in combat, after Alt+Z) gets its timers at once.
- One buff the game hides no longer stops all the other timers from updating.
- Edit Mode icon and menu sizes keep the border at one screen pixel.
- Turning the skin off leaves the icon tint to the game (unusable, out of mana) instead of putting back an old one.
- /fcb debug lists the known buff durations and the last casts, to see why a timer did or did not restart.

# 1.1.1

- Buff timers sit in the centre of the button in a bigger font that follows the button size.
- Buff timers listen to your own buffs only and update once per page turn instead of once per button.
- Turning the skin off now brings back the game's current button art, also after Edit Mode changes.
- Safer hooks into Dominos: a renamed Dominos method can't stop the addon from loading.
- The game's Options page follows a language switch.

# 1.1.0

- Buff timers on buttons: your own buffs show how long they have left on their spell's button.

# 1.0.0

- First release: square action, bag and menu buttons with a thin pixel border, for Dominos or the default bars.
