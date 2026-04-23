import "dart:io";
import "dart:typed_data";

import "package:file_picker/file_picker.dart";

/// Reads file bytes, including from disk when the picker no longer has [PlatformFile.bytes] in memory.
Future<Uint8List?> readPlatformFileBytes(PlatformFile f) async {
  if (f.bytes != null && f.bytes!.isNotEmpty) {
    return f.bytes;
  }
  final p = f.path;
  if (p == null || p.isEmpty) {
    return null;
  }
  return File(p).readAsBytes();
}
