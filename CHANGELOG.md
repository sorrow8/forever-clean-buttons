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
