import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import '../providers/browser_provider.dart';
import '../services/transfer_service.dart';

class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(transferProvider);

    return Scaffold(
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    _StatusCard(t: t),
                    if (t.running && t.url != null) ...[
                      const SizedBox(height: 14),
                      _ConnectCard(url: t.url!, pin: t.pin),
                    ],
                    if (t.received.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ReceivedCard(
                        files: t.received,
                        onOpenFolder: () => Navigator.pop(context, t.dir.path),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _HowTo(folder: t.dir.path),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 8,
        16,
        22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6CC4F8), AppColors.skyDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            color: Colors.white,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wireless Transfer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'PC aur Mobile ke beech, bina cable',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x141E88E5),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    );

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.t});
  final TransferService t;

  @override
  Widget build(BuildContext context) {
    final running = t.running;
    final error = t.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: running
                      ? AppColors.success.withAlpha(38)
                      : AppColors.skySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  running ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
                  color: running ? AppColors.success : AppColors.skyDark,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? 'Transfer ON hai' : 'Transfer band hai',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      running
                          ? 'Ab dusre device se connect karein'
                          : 'Shuru karne ke liye neeche button dabayein',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          running
              ? OutlinedButton.icon(
                  onPressed: () => t.stop(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Band karein'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
              : FilledButton.icon(
                  onPressed: () => t.start(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Transfer shuru karein'),
                ),
        ],
      ),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.url, required this.pin});
  final String url;
  final String pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.skySoft, width: 2),
            ),
            child: QrImageView(data: url, size: 176),
          ),
          const SizedBox(height: 14),
          const Text(
            'QR scan karein, ya browser mein ye address kholein',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.skySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.skyDark,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  color: AppColors.skyDark,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Address copy ho gaya'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PIN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in pin.split(''))
                Container(
                  width: 50,
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.skySoft, width: 2),
                  ),
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceivedCard extends StatelessWidget {
  const _ReceivedCard({required this.files, required this.onOpenFolder});
  final List<String> files;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final shown = files.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mili hui files (${files.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (files.length > shown.length)
            Text(
              '... aur ${files.length - shown.length} files',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onOpenFolder,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Folder kholein'),
          ),
        ],
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo({required this.folder});
  final String folder;

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.skySoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.skyDark,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kaise kaam karta hai?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          step(1, 'Dono devices ek hi Wi-Fi (ya mobile hotspot) par hon.'),
          step(2, 'Is device par "Transfer shuru karein" dabayein.'),
          step(3, 'Dusre device ke browser mein address kholein ya QR scan karein, PIN daalein.'),
          step(4, 'Wahan se files upload karein (yahan aa jayengi) ya yahan ki files download karein.'),
          const SizedBox(height: 8),
          Text(
            'Shared folder:\n$folder',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
