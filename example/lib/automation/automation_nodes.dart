import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

/// Items flowing between workflow nodes (n8n "main" connection).
const itemType = PortType(
  'items',
  color: Color(0xFF98A2B3),
  compatibleWith: {'json', 'any'},
);

const _trigger = NodeStyle(headerColor: Color(0xFFEA580C));
const _flow = NodeStyle(headerColor: Color(0xFF0284C7));
const _data = NodeStyle(headerColor: Color(0xFF7C3AED));
const _action = NodeStyle(headerColor: Color(0xFF16A34A));
const _ai = NodeStyle(headerColor: Color(0xFFDB2777));

const _in = PortSpec.input('in', label: 'Input', type: itemType, maxLinks: -1);
const _out = PortSpec.output('out', label: 'Output', type: itemType);

const _kv = TableParam([
  TableColumn('name', TextParam(hint: 'name'), label: 'Name'),
  TableColumn('value', TextParam(hint: 'value'), label: 'Value'),
]);

/// Definitions of the automation showcase.
final List<NodeDefinition> automationNodes = [
  const NodeDefinition(
    type: 'trigger.manual',
    title: 'Manual Trigger',
    category: 'Triggers',
    icon: Icons.play_circle_outline,
    description: 'Starts the workflow when you press Execute.',
    tags: ['start', 'click'],
    style: _trigger,
    ports: [_out],
  ),
  NodeDefinition(
    type: 'trigger.schedule',
    title: 'Schedule',
    category: 'Triggers',
    icon: Icons.schedule,
    description: 'Runs on a cron schedule.',
    tags: const ['cron', 'timer', 'interval'],
    style: _trigger,
    variant: NodeVariant.dynamic,
    ports: const [_out],
    params: [
      const ParamSpec(
        'cron',
        TextParam(defaultValue: '*/5 * * * *'),
        label: 'Cron',
        showInNode: true,
      ),
      ParamSpec(
        'timezone',
        EnumParam.values(['UTC', 'Europe/Paris', 'America/New_York']),
        label: 'Timezone',
      ),
      const ParamSpec('start', DateTimeParam(), label: 'Start at'),
    ],
  ),
  NodeDefinition(
    type: 'trigger.webhook',
    title: 'Webhook',
    category: 'Triggers',
    icon: Icons.webhook,
    description: 'Starts when an HTTP request hits the URL.',
    tags: const ['http', 'api'],
    style: _trigger,
    variant: NodeVariant.dynamic,
    ports: const [_out],
    params: [
      ParamSpec(
        'method',
        EnumParam.values([
          'GET',
          'POST',
          'PUT',
          'DELETE',
        ], defaultValue: 'POST'),
        label: 'Method',
        showInNode: true,
      ),
      const ParamSpec(
        'path',
        TextParam(defaultValue: '/orders'),
        label: 'Path',
        showInNode: true,
      ),
      ParamSpec(
        'auth',
        EnumParam.values(['None', 'Header', 'Basic']),
        label: 'Auth',
      ),
      const ParamSpec('secret', PasswordParam(), label: 'Secret'),
    ],
  ),
  NodeDefinition(
    type: 'http.request',
    title: 'HTTP Request',
    category: 'Actions',
    icon: Icons.http,
    description: 'Calls a REST API.',
    tags: const ['rest', 'api', 'fetch'],
    style: _action,
    variant: NodeVariant.dynamic,
    defaultSize: const Size(240, 150),
    ports: const [_in, _out],
    params: [
      ParamSpec(
        'method',
        EnumParam.values(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']),
        label: 'Method',
        showInNode: true,
      ),
      const ParamSpec(
        'url',
        TextParam(hint: 'https://api.example.com'),
        label: 'URL',
        showInNode: true,
      ),
      const ParamSpec('headers', _kv, label: 'Headers', group: 'Request'),
      const ParamSpec(
        'query',
        _kv,
        label: 'Query parameters',
        group: 'Request',
      ),
      const ParamSpec(
        'body',
        JsonParam(defaultValue: {'id': 1}),
        label: 'Body',
        group: 'Request',
      ),
      const ParamSpec(
        'timeout',
        QuantityParam(['ms', 's'], defaultValue: Quantity(10, 's')),
        label: 'Timeout',
        group: 'Options',
      ),
      const ParamSpec(
        'retries',
        IntParam(min: 0, max: 5, slider: true),
        label: 'Retries',
        group: 'Options',
      ),
      const ParamSpec(
        'apiKey',
        PasswordParam(),
        label: 'API key',
        group: 'Auth',
      ),
    ],
  ),
  NodeDefinition(
    type: 'flow.if',
    title: 'IF',
    category: 'Flow',
    icon: Icons.call_split,
    description: 'Routes items on a condition.',
    tags: const ['condition', 'branch'],
    style: _flow,
    variant: NodeVariant.dynamic,
    ports: const [
      _in,
      PortSpec.output('true', label: 'true', type: itemType),
      PortSpec.output('false', label: 'false', type: itemType),
    ],
    params: [
      const ParamSpec(
        'left',
        ExpressionParam(defaultValue: 'item.total'),
        label: 'Value',
      ),
      ParamSpec(
        'op',
        EnumParam.values(['>', '<', '=', '≠', 'contains', 'is empty']),
        label: 'Operator',
        showInNode: true,
      ),
      const ParamSpec(
        'right',
        TextParam(defaultValue: '100'),
        label: 'Compare to',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'flow.switch',
    title: 'Switch',
    category: 'Flow',
    icon: Icons.alt_route,
    description: 'Routes items to one of several outputs.',
    style: _flow,
    ports: [
      _in,
      PortSpec.output('c1', label: 'Rule 1', type: itemType),
      PortSpec.output('c2', label: 'Rule 2', type: itemType),
      PortSpec.output('c3', label: 'Rule 3', type: itemType),
      PortSpec.output('fallback', label: 'Fallback', type: itemType),
    ],
    params: [
      ParamSpec(
        'field',
        TextParam(defaultValue: 'item.country'),
        label: 'Field',
      ),
      ParamSpec(
        'rules',
        ListParam(TextParam(), defaultValue: ['FR', 'US', 'DE']),
        label: 'Rules',
      ),
    ],
  ),
  NodeDefinition(
    type: 'flow.merge',
    title: 'Merge',
    category: 'Flow',
    icon: Icons.merge,
    description: 'Combines several branches. Use the node menu to add inputs.',
    style: _flow,
    variant: NodeVariant.dynamic,
    ports: const [
      PortSpec.input('in1', label: 'Input 1', type: itemType),
      PortSpec.input('in2', label: 'Input 2', type: itemType),
      _out,
    ],
    params: [
      ParamSpec(
        'mode',
        EnumParam.values(['Append', 'By key', 'Wait all']),
        label: 'Mode',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'flow.wait',
    title: 'Wait',
    category: 'Flow',
    icon: Icons.hourglass_bottom,
    style: _flow,
    variant: NodeVariant.dynamic,
    ports: [_in, _out],
    params: [
      ParamSpec(
        'delay',
        QuantityParam(['ms', 's', 'min', 'h'], defaultValue: Quantity(2, 's')),
        label: 'Delay',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'flow.loop',
    title: 'Loop Over Items',
    category: 'Flow',
    icon: Icons.loop,
    style: _flow,
    variant: NodeVariant.dynamic,
    ports: [
      _in,
      PortSpec.output('loop', label: 'loop', type: itemType),
      PortSpec.output('done', label: 'done', type: itemType),
    ],
    params: [
      ParamSpec(
        'batch',
        IntParam(min: 1, max: 100, slider: true, defaultValue: 10),
        label: 'Batch size',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'data.set',
    title: 'Edit Fields',
    category: 'Data',
    icon: Icons.edit_note,
    description: 'Adds or overwrites fields.',
    tags: ['set', 'map', 'transform'],
    style: _data,
    ports: [_in, _out],
    params: [ParamSpec('fields', _kv, label: 'Fields')],
  ),
  NodeDefinition(
    type: 'data.code',
    title: 'Code',
    category: 'Data',
    icon: Icons.code,
    description: 'Runs custom code for each item.',
    tags: const ['javascript', 'python', 'script'],
    style: _data,
    variant: NodeVariant.dynamic,
    ports: const [_in, _out],
    params: [
      ParamSpec(
        'language',
        EnumParam.values(['JavaScript', 'Python'], segmented: true),
        label: 'Language',
        showInNode: true,
      ),
      const ParamSpec(
        'code',
        CodeParam(
          language: 'javascript',
          defaultValue: 'return items.map(i => ({...i, vip: i.total > 500}));',
        ),
        label: 'Code',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'data.filter',
    title: 'Filter',
    category: 'Data',
    icon: Icons.filter_alt_outlined,
    style: _data,
    variant: NodeVariant.dynamic,
    ports: [_in, _out],
    params: [
      ParamSpec(
        'condition',
        ExpressionParam(
          defaultValue: 'item.paid == true',
          variables: ['item', 'index'],
        ),
        label: 'Keep if',
        showInNode: true,
      ),
    ],
  ),
  NodeDefinition(
    type: 'data.sort',
    title: 'Sort',
    category: 'Data',
    icon: Icons.sort,
    style: _data,
    variant: NodeVariant.dynamic,
    ports: const [_in, _out],
    params: [
      const ParamSpec(
        'field',
        TextParam(defaultValue: 'total'),
        label: 'Field',
      ),
      ParamSpec(
        'order',
        EnumParam.values(['asc', 'desc'], segmented: true),
        label: 'Order',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'action.email',
    title: 'Send Email',
    category: 'Actions',
    icon: Icons.mail_outline,
    style: _action,
    variant: NodeVariant.dynamic,
    ports: [_in, _out],
    params: [
      ParamSpec(
        'to',
        TextParam(defaultValue: 'ops@example.com'),
        label: 'To',
        showInNode: true,
      ),
      ParamSpec(
        'subject',
        TextParam(defaultValue: 'New order'),
        label: 'Subject',
      ),
      ParamSpec(
        'body',
        MultilineTextParam(defaultValue: 'Order {{id}} received.'),
        label: 'Body',
      ),
      ParamSpec(
        'priority',
        MultiSelectParam([
          ParamOption('high', 'High priority'),
          ParamOption('receipt', 'Read receipt'),
        ]),
        label: 'Options',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'action.slack',
    title: 'Slack',
    category: 'Actions',
    icon: Icons.chat_bubble_outline,
    style: _action,
    variant: NodeVariant.dynamic,
    ports: [_in, _out],
    params: [
      ParamSpec(
        'channel',
        TextParam(defaultValue: '#orders'),
        label: 'Channel',
        showInNode: true,
      ),
      ParamSpec(
        'message',
        MultilineTextParam(defaultValue: ':tada: {{total}} €'),
        label: 'Message',
      ),
    ],
  ),
  NodeDefinition(
    type: 'action.db',
    title: 'Postgres',
    category: 'Actions',
    icon: Icons.storage,
    style: _action,
    variant: NodeVariant.dynamic,
    ports: const [_in, _out],
    params: [
      ParamSpec(
        'operation',
        EnumParam.values(['Insert', 'Update', 'Select', 'Upsert']),
        label: 'Operation',
        showInNode: true,
      ),
      const ParamSpec(
        'table',
        TextParam(defaultValue: 'orders'),
        label: 'Table',
      ),
      const ParamSpec(
        'sql',
        CodeParam(language: 'sql', defaultValue: 'SELECT * FROM orders;'),
        label: 'Query',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ai.agent',
    title: 'AI Agent',
    category: 'AI',
    icon: Icons.auto_awesome,
    description: 'Summarizes or classifies items with an LLM.',
    tags: const ['llm', 'claude', 'gpt'],
    style: _ai,
    variant: NodeVariant.dynamic,
    defaultSize: const Size(230, 150),
    ports: const [_in, _out],
    params: [
      ParamSpec(
        'model',
        EnumParam.values([
          'claude-opus-5-5',
          'claude-sonnet-5-5',
          'claude-haiku-5-5',
        ]),
        label: 'Model',
        showInNode: true,
      ),
      const ParamSpec(
        'temperature',
        DoubleParam(
          min: 0,
          max: 1,
          step: 0.05,
          slider: true,
          defaultValue: 0.2,
        ),
        label: 'Temperature',
        showInNode: true,
      ),
      const ParamSpec(
        'prompt',
        MultilineTextParam(
          defaultValue: 'Classify this order as priority or standard.',
        ),
        label: 'Prompt',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'output.respond',
    title: 'Respond to Webhook',
    category: 'Actions',
    icon: Icons.reply,
    style: _action,
    ports: [_in],
    params: [
      ParamSpec(
        'status',
        IntParam(min: 100, max: 599, defaultValue: 200),
        label: 'Status',
      ),
      ParamSpec('body', JsonParam(defaultValue: {'ok': true}), label: 'Body'),
    ],
  ),
];
