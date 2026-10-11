import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Deletes the selection.
class DeleteSelectionIntent extends Intent {
  /// Creates the intent.
  const DeleteSelectionIntent();
}

/// Copies the selection.
class CopySelectionIntent extends Intent {
  /// Creates the intent.
  const CopySelectionIntent();
}

/// Cuts the selection.
class CutSelectionIntent extends Intent {
  /// Creates the intent.
  const CutSelectionIntent();
}

/// Pastes the clipboard.
class PasteIntent extends Intent {
  /// Creates the intent.
  const PasteIntent();
}

/// Duplicates the selection.
class DuplicateSelectionIntent extends Intent {
  /// Creates the intent.
  const DuplicateSelectionIntent();
}

/// Undoes the last step.
class UndoIntent extends Intent {
  /// Creates the intent.
  const UndoIntent();
}

/// Redoes the last undone step.
class RedoIntent extends Intent {
  /// Creates the intent.
  const RedoIntent();
}

/// Selects everything.
class SelectAllIntent extends Intent {
  /// Creates the intent.
  const SelectAllIntent();
}

/// Clears the selection / cancels the current interaction.
class CancelIntent extends Intent {
  /// Creates the intent.
  const CancelIntent();
}

/// Groups the selection into a super node.
class GroupSelectionIntent extends Intent {
  /// Creates the intent.
  const GroupSelectionIntent();
}

/// Ungroups the selected super nodes.
class UngroupSelectionIntent extends Intent {
  /// Creates the intent.
  const UngroupSelectionIntent();
}

/// Toggles the lock of the selection.
class ToggleLockIntent extends Intent {
  /// Creates the intent.
  const ToggleLockIntent();
}

/// Moves the selection by a number of steps.
class NudgeSelectionIntent extends Intent {
  /// Creates the intent.
  const NudgeSelectionIntent(this.dx, this.dy, {this.large = false});

  /// Horizontal steps.
  final int dx;

  /// Vertical steps.
  final int dy;

  /// Whether to use the large step.
  final bool large;
}

/// Fits the graph in the viewport.
class FitViewIntent extends Intent {
  /// Creates the intent.
  const FitViewIntent();
}

/// Zooms in.
class ZoomInIntent extends Intent {
  /// Creates the intent.
  const ZoomInIntent();
}

/// Zooms out.
class ZoomOutIntent extends Intent {
  /// Creates the intent.
  const ZoomOutIntent();
}

/// Leaves the current super node.
class ExitScopeIntent extends Intent {
  /// Creates the intent.
  const ExitScopeIntent();
}

/// Default key bindings of the editor. Pass a modified copy to
/// `NodeCanvas.shortcuts` to remap them.
abstract final class NodeEditorShortcuts {
  static Map<ShortcutActivator, Intent> _both(
    LogicalKeyboardKey key,
    Intent intent, {
    bool shift = false,
  }) => {
    SingleActivator(key, control: true, shift: shift): intent,
    SingleActivator(key, meta: true, shift: shift): intent,
  };

  /// The default bindings.
  static final Map<ShortcutActivator, Intent> defaults = {
    const SingleActivator(LogicalKeyboardKey.delete):
        const DeleteSelectionIntent(),
    const SingleActivator(LogicalKeyboardKey.backspace):
        const DeleteSelectionIntent(),
    ..._both(LogicalKeyboardKey.keyC, const CopySelectionIntent()),
    ..._both(LogicalKeyboardKey.keyX, const CutSelectionIntent()),
    ..._both(LogicalKeyboardKey.keyV, const PasteIntent()),
    ..._both(LogicalKeyboardKey.keyD, const DuplicateSelectionIntent()),
    ..._both(LogicalKeyboardKey.keyZ, const UndoIntent()),
    ..._both(LogicalKeyboardKey.keyY, const RedoIntent()),
    ..._both(LogicalKeyboardKey.keyZ, const RedoIntent(), shift: true),
    ..._both(LogicalKeyboardKey.keyA, const SelectAllIntent()),
    ..._both(LogicalKeyboardKey.keyG, const GroupSelectionIntent()),
    ..._both(
      LogicalKeyboardKey.keyG,
      const UngroupSelectionIntent(),
      shift: true,
    ),
    ..._both(LogicalKeyboardKey.keyL, const ToggleLockIntent()),
    const SingleActivator(LogicalKeyboardKey.escape): const CancelIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF, shift: true):
        const FitViewIntent(),
    ..._both(LogicalKeyboardKey.equal, const ZoomInIntent()),
    ..._both(LogicalKeyboardKey.add, const ZoomInIntent()),
    ..._both(LogicalKeyboardKey.minus, const ZoomOutIntent()),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const NudgeSelectionIntent(-1, 0),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const NudgeSelectionIntent(1, 0),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const NudgeSelectionIntent(0, -1),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const NudgeSelectionIntent(0, 1),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
        const NudgeSelectionIntent(-1, 0, large: true),
    const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
        const NudgeSelectionIntent(1, 0, large: true),
    const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
        const NudgeSelectionIntent(0, -1, large: true),
    const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
        const NudgeSelectionIntent(0, 1, large: true),
    const SingleActivator(LogicalKeyboardKey.backspace, alt: true):
        const ExitScopeIntent(),
  };
}
