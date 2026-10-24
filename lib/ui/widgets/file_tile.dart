import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/file_item.dart';
import 'file_icon.dart';

/// Ek file/folder ki row.
///  - Right swipe  => Rename
///  - Left swipe   => Delete (Trash + Undo)
///  - Pencil icon  => 1-tap Rename (sirf PC par; mobile par screen saaf rakhne ke liye swipe)
///  - Star       => ⭐ Important (marked items par star dikhta hai)
///  - Long press / icon tap => Select
///  - Subtitle: file => size • time, folder => "N items" (khali => "0 items")
const _star = Color(0xFFFFB300);

class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.dim,
    required this.showPath,
    required this.showTime,
    required this.isFav,
    required this.onStar,
    required this.wide,
    required this.onTap,
    required this.onLongPress,
    required this.onCheck,
    required this.onRename,
    required this.onDelete,
  });

  final FileItem item;
  final bool selected;
  final bool selecting;
  final bool dim;
  final bool showPath;
  final bool showTime;
  final bool isFav;
  final VoidCallback onStar;
  final bool wide;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCheck;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final base = item.isDir ? item.itemsLabel : formatSize(item.size);
    final meta = showTime ? '$base • ${formatTime(item.modified)}' : base;
    final emptyFolder = item.isDir && item.isEmpty;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.skySoft : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.sky : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141E88E5),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCheck,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: selected
                        ? Container(
                            key: const ValueKey('checked'),
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.skyDark,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          )
                        : FileIconBox(item, key: const ValueKey('icon')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        showPath
                            ? '$meta • ${p.basename(p.dirname(item.path))}'
                            : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              emptyFolder ? FontWeight.w700 : FontWeight.w400,
                          color: emptyFolder
                              ? AppColors.skyDark
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!selecting && wide) ...[
                  IconButton(
                    tooltip: isFav ? 'Important se hatayein' : 'Important mark karein',
                    onPressed: onStar,
                    color: _star,
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 23,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename (F2)',
                    onPressed: onRename,
                    color: AppColors.skyDark,
                    icon: const Icon(Icons.edit_outlined, size: 21),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    color: AppColors.danger,
                    icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  ),
                ] else if (isFav)
                  IconButton(
                    tooltip: 'Important se hatayein',
                    onPressed: onStar,
                    color: _star,
                    icon: const Icon(Icons.star_rounded, size: 23),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Dismissible(
        key: ValueKey(item.path),
        direction:
            selecting ? DismissDirection.none : DismissDirection.horizontal,
        background: _swipeBg(
          Alignment.centerLeft,
          AppColors.sky,
          Icons.drive_file_rename_outline_rounded,
          'Rename',
        ),
        secondaryBackground: _swipeBg(
          Alignment.centerRight,
          AppColors.danger,
          Icons.delete_outline_rounded,
          'Delete',
        ),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            onRename(); // dialog khulega, tile wapas apni jagah
            return false;
          }
          return true;
        },
        onDismissed: (_) => onDelete(),
        child: tile,
      ),
    );
  }

  Widget _swipeBg(Alignment align, Color color, IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: align,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
