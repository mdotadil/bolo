import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

abstract class PhotoPicker {
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir});
}

class ImagePickerPhotoPicker implements PhotoPicker {
  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return null;
      // Copy into our own directory so the card survives source-photo deletion.
      final dest =
          '${saveDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(picked.path).copy(dest);
      return dest;
    } catch (_) {
      // Permission denied, disk full, source file gone, etc. Treat the same
      // as a user cancel so the sheet stays open and responsive.
      return null;
    }
  }
}

final photoPickerProvider =
    Provider<PhotoPicker>((ref) => ImagePickerPhotoPicker());
