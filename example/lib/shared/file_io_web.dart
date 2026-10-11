import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// Minimal DOM bindings through dart:js_interop (no package dependency).

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external String _createObjectURL(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _Element createElement(String tag);
  external _Element get body;
}

extension type _Element._(JSObject _) implements JSObject {
  external set href(String v);
  external set download(String v);
  external set type(String v);
  external set accept(String v);
  external set onchange(JSFunction f);
  external _FileList? get files;
  external void click();
  external void remove();
  external void append(_Element child);
}

extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _File? item(int index);
}

extension type _File._(JSObject _) implements JSObject {
  external String get name;
  external JSPromise<JSString> text();
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

bool get canUseBrowserFiles => true;

void downloadText(
  String name,
  String text, {
  String mime = 'application/json',
}) {
  final blob = _Blob([text.toJS].toJS, _BlobOptions(type: mime));
  final url = _createObjectURL(blob);
  final a = _document.createElement('a')
    ..href = url
    ..download = name;
  _document.body.append(a);
  a.click();
  a.remove();
  _revokeObjectURL(url);
}

Future<_File?> _pick(String accept) {
  final completer = Completer<_File?>();
  final input = _document.createElement('input')
    ..type = 'file'
    ..accept = accept;
  input.onchange = ((JSAny _) {
    final files = input.files;
    completer.complete(
      files == null || files.length == 0 ? null : files.item(0),
    );
  }).toJS;
  input.click();
  return completer.future;
}

Future<(String, String)?> pickTextFile({String accept = '.json'}) async {
  final file = await _pick(accept);
  if (file == null) return null;
  final text = await file.text().toDart;
  return (file.name, text.toDart);
}

Future<(String, Uint8List)?> pickBinaryFile({String accept = 'image/*'}) async {
  final file = await _pick(accept);
  if (file == null) return null;
  final buffer = await file.arrayBuffer().toDart;
  return (file.name, buffer.toDart.asUint8List());
}
