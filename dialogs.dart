import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme.dart';
import '../models/file_item.dart';
import '../services/file_service.dart';

Dialog _shell({required Widget child}) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(padding: const EdgeInsets.all(22), child: child),
      ),
    );

Widget _title(IconData icon, String text) => Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.skySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.skyDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );

InputDecoration _field(String hint, {String? error, String? label}) =>
    InputDecoration(
      hintText: hint,
      labelText: label,
      errorText: error,
      filled: true,
      fillColor: AppColors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.sky, width: 2),
      ),
    );

// ---------------------------------------------------------------------------
// Rename / New folder (ek hi dialog dono ke liye)
// ---------------------------------------------------------------------------

Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
  bool selectBase = false,
  IconData icon = Icons.edit_rounded,
  String hint = 'Naam likhein',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      confirm: confirm,
      initial: initial,
      selectBase: selectBase,
      icon: icon,
      hint: hint,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirm,
    required this.initial,
    required this.selectBase,
    required this.icon,
    required this.hint,
  });

  final String title;
  final String confirm;
  final String initial;
  final bool selectBase;
  final IconData icon;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    // Rename mein sirf naam select hota hai, extension (.jpg) nahi
    final extLen = widget.selectBase ? p.extension(widget.initial).length : 0;
    _c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length - extLen,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    final err = FileService.validateName(v);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return _shell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(widget.icon, widget.title),
          const SizedBox(height: 18),
          TextField(
            controller: _c,
            autofocus: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: _field(widget.hint, error: _error),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: Text(widget.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Batch rename (prefix / suffix / numbering) + live preview
// ---------------------------------------------------------------------------

Future<BatchOptions?> showBatchRenameDialog(
  BuildContext context,
  List<FileItem> items,
) {
  return showDialog<BatchOptions>(
    context: context,
    builder: (_) => _BatchDialog(items: items),
  );
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({required this.items});
  final List<FileItem> items;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  final _prefix = TextEditingController();
  final _suffix = TextEditingController();
  bool _numbering = false;

  @override
  void dispose() {
    _prefix.dispose();
    _suffix.dispose();
    super.dispose();
  }

  BatchOptions get _options => BatchOptions(
        prefix: _prefix.text,
        suffix: _suffix.text,
        numbering: _numbering,
      );

  bool get _canApply =>
      _prefix.text.isNotEmpty || _suffix.text.isNotEmpty || _numbering;

  @override
  Widget build(BuildContext context) {
    final o = _options;
    final preview = widget.items.take(3).toList();

    return _shell(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              Icons.drive_file_rename_outline_rounded,
              'Batch Rename (${widget.items.length} files)',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _prefix,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: _field('jaise: Trip_', label: 'Prefix (naam se pehle)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _suffix,
              onChanged: (_) => setState(() {}),
              decoration: _field('jaise: _final', label: 'Suffix (naam ke baad)'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _numbering,
              onChanged: (v) => setState(() => _numbering = v),
              title: const Text(
                'Numbering lagayein (_01, _02 ...)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.skySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.skyDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < preview.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${preview[i].name}  →  ${FileService.buildBatchName(preview[i].name, o, i, isDir: preview[i].isDir)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  if (widget.items.length > 3)
                    Text(
                      '... aur ${widget.items.length - 3} files',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canApply ? () => Navigator.pop(context, o) : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('Rename karein'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
