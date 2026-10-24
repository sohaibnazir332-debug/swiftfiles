import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/file_item.dart';

(IconData, Color) fileVisual(FileItem i) {
  if (i.isDir) {
    // Khali folder halka aur "khula" dikhta hai, taake bahar se hi pata chal jaye
    return i.isEmpty
        ? (Icons.folder_open_rounded, const Color(0xFF9CCDF2))
        : (Icons.folder_rounded, AppColors.sky);
  }
  if (i.ext == 'pdf') {
    return (Icons.picture_as_pdf_rounded, const Color(0xFFEF5350));
  }
  switch (i.category) {
    case FileCategory.images:
      return (Icons.image_rounded, const Color(0xFFAB47BC));
    case FileCategory.videos:
      return (Icons.movie_rounded, const Color(0xFFFF7043));
    case FileCategory.audio:
      return (Icons.music_note_rounded, const Color(0xFF26A69A));
    case FileCategory.documents:
      return (Icons.description_rounded, const Color(0xFF42A5F5));
    case FileCategory.archives:
      return (Icons.folder_zip_rounded, const Color(0xFFFFB300));
    case FileCategory.all:
      return (Icons.insert_drive_file_rounded, const Color(0xFF90A4AE));
  }
}

IconData categoryIcon(FileCategory c) => switch (c) {
      FileCategory.all => Icons.apps_rounded,
      FileCategory.images => Icons.image_rounded,
      FileCategory.videos => Icons.movie_rounded,
      FileCategory.audio => Icons.music_note_rounded,
      FileCategory.documents => Icons.description_rounded,
      FileCategory.archives => Icons.folder_zip_rounded,
    };

class FileIconBox extends StatelessWidget {
  const FileIconBox(this.item, {super.key, this.size = 46});

  final FileItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = fileVisual(item);
    // Images ka chhota thumbnail (cacheWidth se memory kam rehti hai)
    if (!item.isDir && item.category == FileCategory.images && item.ext != 'svg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            File(item.path),
            fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _box(icon, color),
          ),
        ),
      );
    }
    return _box(icon, color);
  }

  Widget _box(IconData icon, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}
