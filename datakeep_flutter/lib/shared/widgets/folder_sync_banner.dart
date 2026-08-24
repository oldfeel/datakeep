import 'package:flutter/material.dart';

import '../utils/preview_limits.dart';

/// 文件夹同步状态横幅：百分比、已同步文件数、剩余量、上下行网速
class FolderSyncBanner extends StatelessWidget {
  final Map<String, dynamic> info;
  final Widget? actions;

  const FolderSyncBanner({
    super.key,
    required this.info,
    this.actions,
  });

  static String formatRate(int bps) {
    if (bps <= 0) return '0 B/s';
    return '${formatByteSize(bps)}/s';
  }

  @override
  Widget build(BuildContext context) {
    final status = info['status']?.toString() ?? 'unknown';
    final completion = (info['completion'] as num?)?.toDouble() ?? 0.0;
    final needFiles = (info['needFiles'] as num?)?.toInt() ?? 0;
    final needBytes = (info['needBytes'] as num?)?.toInt() ?? 0;
    final localFiles = (info['localFiles'] as num?)?.toInt() ?? 0;
    final globalFiles = (info['globalFiles'] as num?)?.toInt() ?? 0;
    final pullErrors = (info['pullErrors'] as num?)?.toInt() ?? 0;
    final state = info['state']?.toString() ?? '';
    final pathError = info['pathError']?.toString() ?? '';
    final needsPathFix = info['needsPathFix'] == true;
    final inBps = (info['inBps'] as num?)?.toInt() ?? 0;
    final outBps = (info['outBps'] as num?)?.toInt() ?? 0;
    final stalled = status == 'stalled' || info['stalled'] == true;

    Color color;
    String title;
    IconData icon;
    final pathMissing = info['pathMissing'] == true;
    if (status == 'error' || pullErrors > 0 || needsPathFix) {
      color = Colors.red;
      if (needsPathFix && pathMissing) {
        title = '同步目录不存在';
      } else if (needsPathFix) {
        title = '目录无写入权限';
      } else {
        title = '同步出错';
      }
      icon = Icons.error_outline;
    } else if (stalled) {
      color = Colors.amber.shade800;
      title = '同步停滞';
      icon = Icons.pause_circle_outline;
    } else if (status == 'syncing') {
      color = Colors.orange;
      title = '正在同步…';
      icon = Icons.sync;
    } else if (status == 'waiting') {
      color = Colors.blue;
      title = '等待同步';
      icon = Icons.hourglass_empty;
    } else {
      color = Colors.green;
      title = '已同步';
      icon = Icons.check_circle_outline;
    }

    final showProgress = !stalled &&
        (status == 'syncing' ||
            status == 'waiting' ||
            needFiles > 0 ||
            (completion > 0 && completion < 100));
    final progress = (completion / 100).clamp(0.0, 1.0);

    final detailParts = <String>[];
    if (status == 'waiting') {
      detailParts.add('正在等待与对端建立连接并获取文件列表…');
    } else if (stalled) {
      // 新建文件仍可能正常同步；进度虚高通常是过期/重复索引
      if (localFiles > 0) {
        detailParts.add('本机已有 $localFiles 个文件');
      }
      if (needFiles > 0 || needBytes > 0) {
        final left = <String>[];
        if (needFiles > 0) left.add('$needFiles 项');
        if (needBytes > 0) left.add(formatByteSize(needBytes));
        detailParts.add('引擎仍记待同步 ${left.join(' · ')}（无传输）');
      }
      if (globalFiles > 0 &&
          localFiles > 0 &&
          globalFiles > localFiles * 1.2) {
        detailParts.add('集群计数 $globalFiles（可能含过期索引）');
      }
      detailParts.add('新建文件一般仍可同步；重新扫描无效时请重建索引');
    } else {
      // inSync/global = 本机已对齐集群的文件数 / 集群文件总数
      final totalFiles = globalFiles > 0 ? globalFiles : localFiles;
      final synced = (info['inSyncFiles'] as num?)?.toInt() ??
          (globalFiles > 0
              ? (globalFiles - needFiles).clamp(0, globalFiles)
              : localFiles);
      detailParts.add('已同步 $synced / $totalFiles');
      if (localFiles > 0 &&
          globalFiles > 0 &&
          (localFiles - globalFiles).abs() > 0) {
        detailParts.add('本地 $localFiles');
      }
      if (needFiles > 0 || needBytes > 0) {
        final left = <String>[];
        if (needFiles > 0) left.add('$needFiles 个文件');
        if (needBytes > 0) left.add(formatByteSize(needBytes));
        detailParts.add('待同步 ${left.join(' · ')}');
      }
      if (showProgress && (inBps > 0 || outBps > 0)) {
        detailParts.add('↓ ${formatRate(inBps)}  ↑ ${formatRate(outBps)}');
      } else if (status == 'syncing' && state.isNotEmpty) {
        detailParts.add(state);
      }
    }

    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
                const Spacer(),
                if (!stalled && (completion > 0 || status == 'synced'))
                  Text(
                    '${completion.clamp(0, 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            if (showProgress) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ],
            if (detailParts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detailParts.join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (pathError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pathError,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red),
              ),
            ],
            if (actions != null) ...[
              const SizedBox(height: 8),
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}
