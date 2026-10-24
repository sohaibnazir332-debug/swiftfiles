import 'package:path/path.dart' as p;

enum FileCategory { all, images, videos, audio, documents, archives }

extension FileCategoryX on FileCategory {
  String get label => switch (this) {
        FileCategory.all => 'All',
        FileCategory.images => 'Images',
        FileCategory.videos => 'Videos',
        FileCategory.audio => 'Audio',
        FileCategory.documents => 'Docs',
        FileCategory.archives => 'Archives',
      };
}

const _imageExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg',
};
const _videoExt = {
  'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'flv', 'wmv', 'm4v',
};
const _audioExt = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'opus', 'wma'};
const _docExt = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv',
  'odt', 'ods', 'md', 'epub',
};
const _archiveExt = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'apk', 'iso'};

FileCategory categoryOfExt(String ext) {
  if (_imageExt.contains(ext)) return FileCategory.images;
  if (_videoExt.contains(ext)) return FileCategory.videos;
  if (_audioExt.contains(ext)) return FileCategory.audio;
  if (_docExt.contains(ext)) return FileCategory.documents;
  if (_archiveExt.contains(ext)) return FileCategory.archives;
  return FileCategory.all; // "other"
}

class FileItem {
  const FileItem({
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
    this.childCount = -1,
  });

  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;

  /// Sirf folders ke liye: andar kitni (dikhne wali) cheezein hain (-1 = pata nahi).
  /// 999 se zyada par ginti ruk jati hai (tez rehne ke liye).
  final int childCount;

  bool get isEmpty => isDir && childCount == 0;

  /// Folder ke niche likha jane wala text: "0 items", "1 item", "12 items", "999+ items"
  String get itemsLabel {
    if (childCount < 0) return 'Folder';
    if (childCount == 1) return '1 item';
    if (childCount > 999) return '999+ items';
    return '$childCount items';
  }

  String get name => p.basename(path);

  String get ext =>
      isDir ? '' : p.extension(path).replaceFirst('.', '').toLowerCase();

  /// Folder ya unknown type => FileCategory.all
  FileCategory get category => isDir ? FileCategory.all : categoryOfExt(ext);

  /// ZIP / TAR / TAR.GZ / TGZ: tap par foran extract hoti hain
  bool get isExtractable {
    if (isDir) return false;
    final n = name.toLowerCase();
    return n.endsWith('.zip') ||
        n.endsWith('.tar') ||
        n.endsWith('.tar.gz') ||
        n.endsWith('.tgz');
  }
}
