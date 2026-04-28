import "dart:typed_data";

import "package:file_picker/file_picker.dart";

/// Web: only in-memory [PlatformFile.bytes] is available.
Future<Uint8List?> readPlatformFileBytes(PlatformFile f) async {
  if (f.bytes != null && f.bytes!.isNotEmpty) {
    return f.bytes;
  }
  return null;
}
