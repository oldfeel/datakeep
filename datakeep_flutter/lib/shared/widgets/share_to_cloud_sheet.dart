import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/api_service.dart';
import '../../shared/utils/local_file_path.dart';

/// 分享本机文件：系统分享（微信/邮件）或 BT 磁力链。
Future<void> showShareToCloudSheet(
  BuildContext context, {
  String folderPath = '',
  String relativePath = '',
  String? localAbsolutePath,
}) async {
  var localPath = localAbsolutePath?.trim() ?? '';
  if (localPath.isEmpty) {
    localPath = folderPath.isEmpty
        ? relativePath
        : joinLocalFilePath(folderPath, relativePath);
  }

  if (localPath.isEmpty || !await File(localPath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件不在本机，请先同步或下载后再分享'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  final fileName = localPath.split(Platform.pathSeparator).last;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '分享「$fileName」',
              style: Theme.of(ctx).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('系统分享'),
            subtitle: const Text('微信、邮件等发送文件本体'),
            onTap: () {
              Navigator.pop(ctx);
              _shareViaSystem(context, localPath, fileName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('BT / 磁力链'),
            subtitle: const Text('生成磁力链，对方用 BT 客户端下载'),
            onTap: () {
              Navigator.pop(ctx);
              _shareViaMagnet(
                context,
                folderPath: folderPath,
                relativePath: relativePath.isNotEmpty
                    ? relativePath
                    : fileName,
                fileName: fileName,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _shareViaSystem(
  BuildContext context,
  String localPath,
  String fileName,
) async {
  try {
    await Share.shareXFiles(
      [XFile(localPath, name: fileName)],
      subject: fileName,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('分享失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _shareViaMagnet(
  BuildContext context, {
  required String folderPath,
  required String relativePath,
  required String fileName,
}) async {
  if (folderPath.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法生成磁力链：缺少同步文件夹路径'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('正在生成磁力链…')),
        ],
      ),
    ),
  );

  try {
    final data = await ApiService.createShareTorrent(
      folderPath: folderPath,
      relativePath: relativePath,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    final magnet = data['magnetUrl']?.toString() ?? '';
    if (magnet.isEmpty) {
      throw Exception('未返回磁力链');
    }
    final torrentFileName =
        data['torrentFileName']?.toString() ?? '$fileName.torrent';
    final torrentBase64 = data['torrentBase64']?.toString() ?? '';
    if (!context.mounted) return;
    await _showMagnetDialog(
      context,
      fileName: fileName,
      magnetUrl: magnet,
      torrentFileName: torrentFileName,
      torrentBase64: torrentBase64,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成磁力链失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _showMagnetDialog(
  BuildContext context, {
  required String fileName,
  required String magnetUrl,
  required String torrentFileName,
  required String torrentBase64,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('磁力链 · $fileName'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              magnetUrl,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Text(
              '对方需使用 BT 客户端（如 qBittorrent、迅雷）添加磁力链下载。'
              '当前版本仅生成链接，请在本机用 BT 客户端对该文件做种，或等待后续版本内置做种。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: magnetUrl));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('已复制磁力链')),
              );
            }
          },
          child: const Text('复制'),
        ),
        FilledButton(
          onPressed: () async {
            await Share.share(magnetUrl, subject: fileName);
          },
          child: const Text('分享链接'),
        ),
        if (torrentBase64.isNotEmpty)
          TextButton(
            onPressed: () async {
              try {
                final bytes = base64Decode(torrentBase64);
                final dir = await getTemporaryDirectory();
                final path = '${dir.path}/$torrentFileName';
                await File(path).writeAsBytes(bytes);
                await Share.shareXFiles(
                  [XFile(path, name: torrentFileName)],
                  subject: torrentFileName,
                );
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('分享种子失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('分享种子'),
          ),
      ],
    ),
  );
}
