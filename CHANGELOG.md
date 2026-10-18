# 1.1.2

- Recasting a buff on yourself in combat restarts its timer from the full duration, instead of counting down the old one.
- Buff timers show time the way the game's buff icons do (seconds up to 90 s, minutes up to 90 m, seconds rounded down) and switch to the new second on time, so they no longer show one second more.
- Where the game hides buff data out of combat too (battlegrounds, arenas, keystones) the last known timers stay instead of vanishing.
- A recast of another rank of the same buff updates every button with that buff.
- Timers update often only while seconds are shown and set the text only when it changes.
- Casts with a hidden target no longer risk a Lua error; failed casts are cleaned up.

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
