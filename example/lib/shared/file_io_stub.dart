import 'dart:typed_data';

/// Whether the platform can download / upload files from the browser.
bool get canUseBrowserFiles => false;

/// Downloads [text] as a file called [name] (web only).
void downloadText(
  String name,
  String text, {
  String mime = 'application/json',
}) {}

/// Lets the user pick a text file; returns (name, content) (web only).
Future<(String, String)?> pickTextFile({String accept = '.json'}) async => null;

/// Lets the user pick a binary file; returns (name, bytes) (web only).
Future<(String, Uint8List)?> pickBinaryFile({
  String accept = 'image/*',
}) async => null;
