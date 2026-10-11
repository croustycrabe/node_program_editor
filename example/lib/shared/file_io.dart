/// Browser file download / upload with a no-op fallback on native targets.
library;

export 'file_io_stub.dart' if (dart.library.js_interop) 'file_io_web.dart';
