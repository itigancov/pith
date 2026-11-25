# The Panel is a stack of Screens

The Panel shows one Screen at a time: the Note at the bottom, and Search (08b) and the Trash (07) on top of it. `PanelController` keeps a stack of `PanelScreen` (view, `preferredFirstResponder`, `handleCancel() -> Bool`, `willHide()`) and knows no concrete Screen, so a new Screen is a new type and a `push`, not a change of the controller.

A stack, not `NSTabViewController` or an enum of states: Screens are not peers the user switches between. Search and the Trash open over the Note and Esc takes them back to it, which is what a stack does. A tab controller brings its own chrome and selection model, and an enum of states makes the controller list every Screen and decide what each Esc does.

The controller owns two things for every Screen, so none of them has to:

- **Esc** goes to the top Screen. If its `handleCancel()` returns `false`, the Panel hides. The Note always returns `false`; Search and the Trash take themselves off the stack and return `true`. An input method takes Esc before any of this.
- **Focus** moves to the `preferredFirstResponder` of the new top Screen whenever it changes, and stays on a sheet while one is up.

Hiding the Panel removes everything above the Note, after telling the top Screen with `willHide()`, so the Panel always opens on the Note. A Screen is told with `willCover()` when another goes on top of it; the Note uses it to save at once.
