# Keyboard shortcuts

Ctrl and ⌘ are interchangeable.

| Keys | Action | Intent |
|---|---|---|
| Delete / Backspace | delete selection (locked nodes stay) | `DeleteSelectionIntent` |
| Ctrl + C / X / V | copy / cut / paste | `CopySelectionIntent`, `CutSelectionIntent`, `PasteIntent` |
| Ctrl + D | duplicate | `DuplicateSelectionIntent` |
| Ctrl + Z | undo | `UndoIntent` |
| Ctrl + Y, Ctrl + Shift + Z | redo | `RedoIntent` |
| Ctrl + A | select all | `SelectAllIntent` |
| Escape | cancel link drag / selection box, clear selection | `CancelIntent` |
| Ctrl + G | group selection into a function | `GroupSelectionIntent` |
| Ctrl + Shift + G | ungroup | `UngroupSelectionIntent` |
| Ctrl + L | lock / unlock selection | `ToggleLockIntent` |
| Arrows (+ Shift) | nudge selection (`nudgeStep` / `nudgeStepLarge`) | `NudgeSelectionIntent` |
| Shift + F | fit view | `FitViewIntent` |
| Ctrl + `=` / `+`, Ctrl + `-` | zoom in / out | `ZoomInIntent`, `ZoomOutIntent` |
| Alt + Backspace | leave the current function | `ExitScopeIntent` |
| Space + drag | pan | (pointer) |

Shortcuts act when the canvas has focus. Text fields inside nodes keep their
own shortcuts (typing Backspace in a field does not delete the node).

## Remapping

```dart
NodeCanvas(
  controller: controller,
  shortcuts: {
    ...NodeEditorShortcuts.defaults,
    const SingleActivator(LogicalKeyboardKey.keyR): const FitViewIntent(),
    const SingleActivator(LogicalKeyboardKey.backspace): const DoNothingAndStopPropagationIntent(),
  },
)
```

To add your own actions, wrap the canvas in `Actions` / `Shortcuts` widgets
with your intents, or add `CallbackShortcuts` above it.
