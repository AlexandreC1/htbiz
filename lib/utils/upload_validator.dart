import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../services/app_exception.dart';

/// Client-side gate for anything we send to Supabase Storage.
///
/// The buckets now enforce size and MIME limits server-side, but a rejection
/// there costs the user a full upload over a slow connection before it fails.
/// This checks first, and it also stops us from deriving a storage key from an
/// attacker-influenced filename.
class UploadValidator {
  UploadValidator._();

  /// Matches the `file_size_limit` set on `htbiz_images`.
  static const int maxImageBytes = 5 * 1024 * 1024;

  /// Matches the `file_size_limit` set on `htbiz_patents`.
  static const int maxDocumentBytes = 10 * 1024 * 1024;

  static const Map<String, String> _imageTypes = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
  };

  static const Map<String, String> _documentTypes = {
    ..._imageTypes,
    '.pdf': 'application/pdf',
  };

  /// Magic-number prefixes. An extension is a claim; these are evidence.
  static const Map<String, List<int>> _signatures = {
    'image/jpeg': [0xFF, 0xD8, 0xFF],
    'image/png': [0x89, 0x50, 0x4E, 0x47],
    'application/pdf': [0x25, 0x50, 0x44, 0x46],
  };

  /// Validates [file] and returns the MIME type to send with the upload.
  ///
  /// Supabase defaults an unknown upload to `application/octet-stream`, which
  /// then fails the bucket's allowed_mime_types check — so we always pass an
  /// explicit content type rather than letting it be inferred.
  static Future<String> validate(File file, {bool allowPdf = false}) async {
    if (!await file.exists()) {
      throw const AppException(
        AppErrorKind.invalid,
        'That file could not be read. Please pick it again.',
      );
    }

    final allowed = allowPdf ? _documentTypes : _imageTypes;
    final limit = allowPdf ? maxDocumentBytes : maxImageBytes;

    final extension = p.extension(file.path).toLowerCase();
    final mime = allowed[extension];
    if (mime == null) {
      throw AppException(
        AppErrorKind.invalid,
        allowPdf
            ? 'Use a JPG, PNG, WEBP or PDF file.'
            : 'Use a JPG, PNG or WEBP image.',
      );
    }

    final length = await file.length();
    if (length == 0) {
      throw const AppException(
        AppErrorKind.invalid,
        'That file is empty. Please pick another one.',
      );
    }
    if (length > limit) {
      throw AppException(
        AppErrorKind.tooLarge,
        'That file is ${_mb(length)} MB. The limit is ${_mb(limit)} MB.',
      );
    }

    await _assertSignatureMatches(file, mime);
    return mime;
  }

  static Future<void> _assertSignatureMatches(File file, String mime) async {
    final expected = _signatures[mime];
    if (expected == null) return; // WEBP is RIFF-based; extension is enough.

    final handle = await file.open();
    Uint8List head;
    try {
      head = await handle.read(expected.length);
    } finally {
      await handle.close();
    }

    if (head.length < expected.length) {
      throw const AppException(
        AppErrorKind.invalid,
        'That file appears to be damaged. Please pick another one.',
      );
    }

    for (var i = 0; i < expected.length; i++) {
      if (head[i] != expected[i]) {
        throw const AppException(
          AppErrorKind.invalid,
          'That file is not a valid image. Please pick another one.',
        );
      }
    }
  }

  /// Builds a storage key we fully control.
  ///
  /// The old code appended `path.extension(imageFile.path)` straight onto the
  /// key. A picked file with no extension produced a key ending in the
  /// timestamp, and one named `x.png/../../y` would have escaped the user's
  /// folder had the bucket policy not caught it.
  static String storageKey({
    required String folder,
    required String userId,
    required String mime,
  }) {
    final extension = _extensionFor(mime);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final salt = (stamp % 100000).toRadixString(36);
    return '$folder/$userId/$stamp-$salt$extension';
  }

  static String _extensionFor(String mime) {
    switch (mime) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'application/pdf':
        return '.pdf';
      case 'image/jpeg':
      default:
        return '.jpg';
    }
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
