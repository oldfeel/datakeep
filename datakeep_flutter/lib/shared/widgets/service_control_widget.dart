import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/syncthing_service_manager.dart';
import '../pages/s3_share_settings_page.dart';
import '../utils/open_syncthing_gui.dart';

/// Syncthing 服务控制组件
class ServiceControlWidget extends StatelessWidget {
  const ServiceControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncthingServiceManager>(
      builder: (context, serviceManager, child) {
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.sync,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Syncthing 服务',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // 状态指示器
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: serviceManager.isRunning
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      serviceManager.isRunning ? '运行中' : '已停止',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const Spacer(),
                    // 控制按钮
                    if (serviceManager.isRunning)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final success = await serviceManager.stop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? '服务已停止'
                                      : '停止服务失败',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop),
                        label: const Text('停止'),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () async {
                          final success = await serviceManager.start();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? '服务已启动'
                                      : '启动服务失败',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('启动'),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        serviceManager.refresh();
                      },
                      tooltip: '刷新状态',
                    ),
                  ],
                ),
                if (serviceManager.status != 'unknown') ...[
                  const SizedBox(height: 8),
                  Text(
                    '状态: ${serviceManager.status}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  '忽略规则、限速、中继等高级项请使用原版管理页，DataKeep 不自建完整设置中心。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => openSyncthingGui(context),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('打开 Syncthing 管理页'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const S3ShareSettingsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cloud_outlined, size: 18),
                    label: const Text('互联网分享 · 存储配置'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

