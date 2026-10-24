import 'package:file_picker/file_picker.dart';

/// A file the seller chose, already read into memory.
class PickedDocument {
  final String name;
  final List<int> bytes;

  const PickedDocument({required this.name, required this.bytes});

  int get sizeBytes => bytes.length;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';

  /// The MIME type the upload declares. The server checks the real type itself.
  String get contentType => switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

/// Picks a KYC document. An interface so the screens can be tested without a
/// native file dialog, and so the plugin is swappable in one place.
abstract class DocumentPicker {
  /// Null when the seller backs out of the dialog — a normal outcome.
  /// [extensions] narrows what the dialog offers (photos only, say).
  Future<PickedDocument?> pick({List<String> extensions = DocumentRules.allowedExtensions});
}

/// What the product-photo upload accepts: images only, at most 10 MB.
class PhotoRules {
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// The upload endpoint's ceiling is 10 MB.
  static const maxBytes = 10 * 1024 * 1024;

  static String? problemWith(PickedDocument doc) {
    if (!allowedExtensions.contains(doc.extension)) return 'Use a JPG, PNG or WebP photo.';
    if (doc.sizeBytes == 0) return 'That file is empty.';
    if (doc.sizeBytes > maxBytes) return 'That photo is over 10 MB. Choose a smaller one.';
    return null;
  }
}

/// What the KYC document upload accepts: images and PDFs, at most 5 MB.
class DocumentRules {
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
  static const maxBytes = 5 * 1024 * 1024;

  /// A message if [doc] would be refused, so the seller finds out before a
  /// slow upload rather than after it.
  static String? problemWith(PickedDocument doc) {
    if (!allowedExtensions.contains(doc.extension)) {
      return 'Use a JPG, PNG, WebP or PDF file.';
    }
    if (doc.sizeBytes > maxBytes) {
      return 'That file is over 5 MB. Choose a smaller scan or photo.';
    }
    if (doc.sizeBytes == 0) return 'That file is empty.';
    return null;
  }
}

class FilePickerDocumentPicker implements DocumentPicker {
  const FilePickerDocumentPicker();

  @override
  Future<PickedDocument?> pick({List<String> extensions = DocumentRules.allowedExtensions}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;

    return PickedDocument(name: file.name, bytes: await file.readAsBytes());
  }
}
