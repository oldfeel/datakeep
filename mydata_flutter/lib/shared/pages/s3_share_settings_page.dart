import 'package:flutter/material.dart';
import '../../core/services/s3_share_config.dart';

/// S3 兼容存储配置页（分享到互联网）
class S3ShareSettingsPage extends StatefulWidget {
  const S3ShareSettingsPage({super.key});

  @override
  State<S3ShareSettingsPage> createState() => _S3ShareSettingsPageState();
}

class _S3ShareSettingsPageState extends State<S3ShareSettingsPage> {
  final _endpoint = TextEditingController();
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();
  final _bucket = TextEditingController();
  final _region = TextEditingController(text: 'us-east-1');
  bool _useSSL = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await S3ShareConfigStore.load();
    if (!mounted) return;
    setState(() {
      _endpoint.text = c.endpoint;
      _accessKey.text = c.accessKey;
      _secretKey.text = c.secretKey;
      _bucket.text = c.bucket;
      _region.text = c.region;
      _useSSL = c.useSSL;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await S3ShareConfigStore.save(S3ShareConfig(
      endpoint: _endpoint.text.trim(),
      accessKey: _accessKey.text.trim(),
      secretKey: _secretKey.text.trim(),
      bucket: _bucket.text.trim(),
      region: _region.text.trim().isEmpty ? 'us-east-1' : _region.text.trim(),
      useSSL: _useSSL,
    ));
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    }
  }

  void _fillQiniu() {
    setState(() {
      _endpoint.text = 's3-cn-east-1.qiniucs.com';
      _region.text = 'cn-east-1';
      _useSSL = true;
    });
  }

  void _fillAliyun() {
    setState(() {
      _endpoint.text = 'oss-cn-hangzhou.aliyuncs.com';
      _region.text = 'oss-cn-hangzhou';
      _useSSL = true;
    });
  }

  void _fillTencent() {
    setState(() {
      _endpoint.text = 'cos.ap-guangzhou.myqcloud.com';
      _region.text = 'ap-guangzhou';
      _useSSL = true;
    });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _bucket.dispose();
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('互联网分享 · 存储配置'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '填写 S3 兼容凭证。成本上优先推荐七牛（外网下载约 0.26 元/GB）；'
            '也可使用已有的阿里云 OSS / 腾讯云 COS / 自建 MinIO。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(label: const Text('填七牛示例'), onPressed: _fillQiniu),
              ActionChip(label: const Text('填阿里云示例'), onPressed: _fillAliyun),
              ActionChip(label: const Text('填腾讯云示例'), onPressed: _fillTencent),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpoint,
            decoration: const InputDecoration(
              labelText: 'Endpoint（不含 https://）',
              hintText: 's3-cn-east-1.qiniucs.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bucket,
            decoration: const InputDecoration(
              labelText: 'Bucket',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _accessKey,
            decoration: const InputDecoration(
              labelText: 'Access Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secretKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Secret Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _region,
            decoration: const InputDecoration(
              labelText: 'Region',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            title: const Text('使用 HTTPS'),
            value: _useSSL,
            onChanged: (v) => setState(() => _useSSL = v),
          ),
        ],
      ),
    );
  }
}
