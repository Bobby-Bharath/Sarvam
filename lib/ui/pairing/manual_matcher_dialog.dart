import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/metadata/filename_tokenizer.dart';
import 'pre_flight_mapping_dialog.dart';

class ManualMatcherDialog {
  static void show(
    BuildContext context, {
    AssetPathEntity? folder,
    AssetEntity? video,
    VoidCallback? onComplete,
  }) async {
    final String initialQuery = folder?.name ?? video?.title ?? '';
    final token = FilenameTokenizer.parse(initialQuery);

    List<AssetEntity> files = [];
    String? folderPath;

    if (folder != null) {
      files = await folder.getAssetListRange(start: 0, end: 1000);
      if (files.isNotEmpty) {
        final firstFile = await files.first.originFile;
        folderPath = firstFile?.parent.path;
      }
    } else if (video != null) {
      files = [video];
      final file = await video.originFile;
      folderPath = file?.parent.path;
    }

    if (context.mounted) {
      PreFlightMappingDialog.show(
        context,
        files: files,
        initialQuery: token.cleanTitle,
        folderId: folder?.id,
        folderPath: folderPath,
        onComplete: onComplete,
      );
    }
  }
}
