/// A high-performance, fully customizable node graph editor engine for
/// Flutter ("React Flow for Flutter").
///
/// Start with a [NodeRegistry] of [NodeDefinition]s, create a
/// [NodeEditorController] and display it with a `NodeEditor` (or compose
/// `NodeCanvas`, `NodePalette`, `NodeMiniMap` and `NodeToolbar` yourself).
library;

export 'src/core/commands.dart';
export 'src/core/config.dart';
export 'src/core/controller.dart';
export 'src/core/edge.dart';
export 'src/core/edge_geometry.dart';
export 'src/core/graph.dart';
export 'src/core/ids.dart';
export 'src/core/io/design_document.dart';
export 'src/core/io/fragment.dart';
export 'src/core/io/graph_codec.dart';
export 'src/core/io/logic_document.dart';
export 'src/core/json.dart'
    show colorFromJson, colorToJson, offsetFromJson, offsetToJson;
export 'src/core/node.dart';
export 'src/core/port_geometry.dart';
export 'src/core/ports.dart';
export 'src/core/spatial_hash_grid.dart';
export 'src/core/supernode/super_node.dart';
export 'src/core/validation.dart';
export 'src/core/viewport.dart';
export 'src/params/param_types.dart';
export 'src/params/param_values.dart';
export 'src/widgets/node_render_context.dart';
