import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/browser_provider.dart';

/// Clean storage indicator: kitni jagah use hui aur kitni khali hai.
/// Agar storage ki info na mile (jaise Android par MainActivity patch na ho)
/// to ye widget chupchap gayab rehta hai.
class StorageCard extends ConsumerWidget {
  const StorageCard({super.key, this.compact = false, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(storageStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();

    final f = stats.fraction;
    final barColor = f > 0.9
        ? AppColors.danger
        : (f > 0.75 ? const Color(0xFFFFB300) : AppColors.sky);
    final title = Platform.isAndroid ? 'Phone Storage' : 'PC Storage';

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: f,
        minHeight: compact ? 7 : 9,
        color: barColor,
        backgroundColor: AppColors.skySoft,
      ),
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.skySoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  '${(f * 100).round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.skyDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            bar,
            const SizedBox(height: 6),
            Text(
              '${formatSize(stats.free)} khali / ${formatSize(stats.total)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.skySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    color: AppColors.skyDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${(f * 100).round()}% use',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: barColor == AppColors.sky
                                  ? AppColors.skyDark
                                  : barColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      bar,
                      const SizedBox(height: 6),
                      Text(
                        '${formatSize(stats.used)} use • ${formatSize(stats.free)} khali'
                        '${onTap != null ? '  •  Saaf karein ›' : ''}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
