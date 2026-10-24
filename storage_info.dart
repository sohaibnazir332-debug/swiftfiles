import 'dart:io';

import 'package:flutter/services.dart';

class StorageStats {
  const StorageStats({required this.total, required this.free});

  final int total;
  final int free;

  int get used => total - free;
  double get fraction => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);
}

/// Storage ki total / khali jagah.
///  - Android: MainActivity.kt ka chhota MethodChannel (README mein step hai)
///  - Windows: PowerShell Get-PSDrive
/// Agar kuch bhi na chale to null aata hai aur indicator chhup jata hai
/// (baaki app par koi asar nahi).
class StorageInfo {
  static const _channel = MethodChannel('swift_files/storage');

  static Future<StorageStats?> read(String rootPath) async {
    try {
      if (Platform.isAndroid) {
        final r = await _channel.invokeMethod<List<dynamic>>('stats');
        if (r == null || r.length < 2) return null;
        final total = (r[0] as num).toInt();
        final free = (r[1] as num).toInt();
        if (total <= 0) return null;
        return StorageStats(total: total, free: free);
      }
      if (Platform.isWindows) {
        final letter = rootPath.isNotEmpty ? rootPath[0].toUpperCase() : 'C';
        if (!RegExp(r'^[A-Z]$').hasMatch(letter)) return null;
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "\$d = Get-PSDrive -Name $letter; Write-Output (\$d.Used.ToString() + ' ' + \$d.Free.ToString())",
        ]);
        if (res.exitCode != 0) return null;
        final parts = res.stdout.toString().trim().split(RegExp(r'\s+'));
        if (parts.length < 2) return null;
        final used = int.parse(parts[0]);
        final free = int.parse(parts[1]);
        if (used + free <= 0) return null;
        return StorageStats(total: used + free, free: free);
      }
    } catch (_) {
      // channel / powershell na mile to chupchap null
    }
    return null;
  }
}
