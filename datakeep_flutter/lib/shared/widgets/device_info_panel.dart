import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/device.dart';
import '../../core/services/api_service.dart';
import '../../features/devices/providers/device_provider.dart';
import 'folder_edit_dialog.dart';

/// 设备基本信息面板，可展开/收起，远程设备支持删除
class DeviceInfoPanel extends StatefulWidget {
  final Device device;
  final VoidCallback? onDeleted;
  final EdgeInsetsGeometry margin;
  final String? wifiName;

  const DeviceInfoPanel({
    super.key,
    required this.device,
    this.onDeleted,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
    this.wifiName,
  });

  @override
  State<DeviceInfoPanel> createState() => _DeviceInfoPanelState();
}

class _DeviceInfoPanelState extends State<DeviceInfoPanel> {
  bool _expanded = false;

  Device get _device => widget.device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = _device.isLocal || _device.connected;

    return Card(
      margin: widget.margin,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _device.isLocal
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                    child: Icon(
                      _device.isLocal ? Icons.computer : Icons.devices,
                      size: 18,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _device.displayName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_device.isLocal) ...[
                              const SizedBox(width: 6),
                              _buildBadge(context, '本机', theme.colorScheme.primary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isOnline ? Icons.circle : Icons.circle_outlined,
                              size: 10,
                              color: isOnline ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _device.isLocal ? '本机设备' : (isOnline ? '在线' : '离线'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(context, '设备 ID', _device.id, monospace: true),
                  if (_device.version != null && _device.version != 'local')
                    _infoRow(context, 'Syncthing 版本', _device.version!),
                  if (_device.connectionType != null &&
                      _device.connectionType != 'local')
                    _infoRow(
                      context,
                      '连接方式',
                      _connectionLabel(_device.connectionType!),
                    ),
                  if (_device.addresses != null && _device.addresses!.isNotEmpty)
                    _infoRow(context, '地址', _device.addresses!.first),
                  if (widget.wifiName != null && widget.wifiName!.isNotEmpty)
                    _infoRow(context, '当前 WiFi', widget.wifiName!),
                  if (!_device.isLocal) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _confirmDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除设备'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _showLocalQr,
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('显示配对二维码'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showLocalQr() async {
    var id = _device.id;
    if (id == 'local' || id.isEmpty) {
      try {
        id = await ApiService.getLocalDeviceId();
      } catch (_) {}
    }
    if (!mounted) return;
    if (id.isEmpty || id == 'local') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取本机设备 ID')),
      );
      return;
    }
    await LocalDeviceQrDialog.show(
      context,
      deviceId: id,
      deviceName: _device.displayName,
    );
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    bool monospace = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 11 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionLabel(String type) {
    switch (type) {
      case 'tcp-server':
        return 'TCP 服务器';
      case 'tcp-client':
        return 'TCP 客户端';
      case 'quic':
        return 'QUIC';
      case 'relay':
        return '中继';
      default:
        return type;
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除设备「${_device.displayName}」吗？\n\n删除后将停止与该设备的同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<DeviceProvider>().removeDevice(_device.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除设备「${_device.displayName}」'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
