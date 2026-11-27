# The Panel does not hide on losing focus

The Panel stays over the other apps until the user hides it: with the Hotkey on a focused Panel, with Esc, with the Hide command, or by opening Settings. Clicking another app, switching Space or entering a full-screen app does not hide it. The Panel is a place to copy to and from, so leaving it for another app is part of using it; hiding on blur made the user press the Hotkey again after every copy.

The Hotkey decides from two facts, whether the Panel is shown and whether it is key (`HotkeyAction.decide`): hidden → show; shown and key → hide; shown and not key → bring forward and focus, so the user can paste at once. An alert sheet that has key counts as the Panel having key, so the Hotkey still hides the Panel while an alert is up. The Open Pith command of the menu bar icon reveals a shown Panel the same way. The Note is saved when the Panel loses key, since hiding no longer does it.

Rejected:

- **A pin toggle.** Extra state to see and manage, and the unpinned default is the bug.
- **A setting "hide on focus loss".** A second behavior to explain and test.

Cost: the Panel can cover other windows until the user hides it, and the Hotkey on an unfocused Panel focuses it instead of hiding it, so hiding it from another app takes two presses.
