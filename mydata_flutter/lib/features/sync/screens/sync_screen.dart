import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/syncthing_service_manager.dart';
import '../../../shared/widgets/service_control_widget.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  Map<String, dynamic>? _syncStatus;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSyncStatus();
  }

  Future<void> _fetchSyncStatus() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final status = await ApiService.getSyncStatus();
      setState(() {
        _syncStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('同步状态'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSyncStatus,
          ),
        ],
      ),
      body: _buildBody(isDesktop),
    );
  }

  Widget _buildBody(bool isDesktop) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchSyncStatus,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_syncStatus == null) {
      return const Center(
        child: Text('暂无同步状态信息'),
      );
    }

    if (isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  // 桌面端布局
  Widget _buildDesktopLayout() {
    return Column(
      children: [
        // 桌面端标题栏
        Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                '同步状态',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _fetchSyncStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        // 桌面端内容 - 使用行布局
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：服务控制和总体状态
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      const ServiceControlWidget(),
                      const SizedBox(height: 24),
                      _buildOverallStatus(),
                      const SizedBox(height: 24),
                      _buildSyncProgress(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // 右侧：最近活动
                Expanded(
                  flex: 1,
                  child: _buildRecentActivity(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 移动端布局
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务控制组件
          const ServiceControlWidget(),
          const SizedBox(height: 16),
          _buildOverallStatus(),
          const SizedBox(height: 24),
          _buildSyncProgress(),
          const SizedBox(height: 24),
          _buildRecentActivity(),
        ],
      ),
    );
  }

  Widget _buildOverallStatus() {
    final serviceManager = Provider.of<SyncthingServiceManager>(context, listen: false);
    final status = _syncStatus?['overall_status'] ?? (serviceManager.isRunning ? 'synced' : 'paused');
    final statusText = _getStatusText(status);
    final statusColor = _getStatusColor(status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '总体状态',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: statusColor,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                      Text(
                        _getStatusDescription(status),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncProgress() {
    final progress = _syncStatus!['sync_progress'] ?? {};
    final totalFiles = progress['total_files'] ?? 0;
    final syncedFiles = progress['synced_files'] ?? 0;
    final progressPercentage = totalFiles > 0 ? (syncedFiles / totalFiles) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同步进度',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progressPercentage,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '已同步: $syncedFiles 个文件',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '总计: $totalFiles 个文件',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '进度: ${(progressPercentage * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final activities = _syncStatus!['recent_activities'] ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近活动',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (activities.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无最近活动'),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  return ListTile(
                    leading: Icon(
                      _getActivityIcon(activity['type']),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(activity['description'] ?? ''),
                    subtitle: Text(
                      _formatDateTime(DateTime.parse(activity['timestamp'] ?? DateTime.now().toIso8601String())),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'syncing':
        return '同步中';
      case 'synced':
        return '已同步';
      case 'error':
        return '同步错误';
      case 'paused':
        return '已暂停';
      default:
        return '未知状态';
    }
  }

  String _getStatusDescription(String status) {
    switch (status) {
      case 'syncing':
        return '正在同步文件，请稍候...';
      case 'synced':
        return '所有文件已同步完成';
      case 'error':
        return '同步过程中出现错误，请检查网络连接';
      case 'paused':
        return '同步已暂停，点击继续同步';
      default:
        return '无法获取同步状态';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'syncing':
        return Colors.orange;
      case 'synced':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'paused':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'syncing':
        return Icons.sync;
      case 'synced':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'paused':
        return Icons.pause_circle;
      default:
        return Icons.help_outline;
    }
  }

  IconData _getActivityIcon(String? type) {
    switch (type) {
      case 'file_added':
        return Icons.add_circle;
      case 'file_modified':
        return Icons.edit;
      case 'file_deleted':
        return Icons.delete;
      case 'sync_started':
        return Icons.sync;
      case 'sync_completed':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} 天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} 小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} 分钟前';
    } else {
      return '刚刚';
    }
  }
}
