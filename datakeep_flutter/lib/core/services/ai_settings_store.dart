import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务商：DeepSeek / 豆包（火山方舟 OpenAI 兼容）
enum AiProvider {
  deepseek,
  doubao;

  String get label => switch (this) {
        AiProvider.deepseek => 'DeepSeek',
        AiProvider.doubao => '豆包',
      };

  static AiProvider fromId(String? id) {
    return switch (id) {
      'doubao' => AiProvider.doubao,
      _ => AiProvider.deepseek,
    };
  }

  String get id => name;
}

/// DeepSeek / 豆包 API Key 与默认模型（SharedPreferences）
class AiSettingsStore {
  AiSettingsStore._();

  static const _kProvider = 'ai_provider';
  static const _kDeepseekKey = 'ai_deepseek_api_key';
  static const _kDoubaoKey = 'ai_doubao_api_key';
  static const _kDeepseekModel = 'ai_deepseek_model';
  static const _kDoubaoModel = 'ai_doubao_model';
  static const _kDoubaoBase = 'ai_doubao_base_url';

  static const defaultDeepseekModel = 'deepseek-flash';
  static const defaultDoubaoModel = 'doubao-seed-1-6-250615';
  static const defaultDoubaoBase =
      'https://ark.cn-beijing.volces.com/api/v3';

  static Future<AiProvider> getProvider() async {
    final p = await SharedPreferences.getInstance();
    return AiProvider.fromId(p.getString(_kProvider));
  }

  static Future<void> setProvider(AiProvider provider) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, provider.id);
  }

  static Future<String> getApiKey(AiProvider provider) async {
    final p = await SharedPreferences.getInstance();
    return switch (provider) {
      AiProvider.deepseek => p.getString(_kDeepseekKey) ?? '',
      AiProvider.doubao => p.getString(_kDoubaoKey) ?? '',
    };
  }

  static Future<void> setApiKey(AiProvider provider, String key) async {
    final p = await SharedPreferences.getInstance();
    final v = key.trim();
    switch (provider) {
      case AiProvider.deepseek:
        await p.setString(_kDeepseekKey, v);
      case AiProvider.doubao:
        await p.setString(_kDoubaoKey, v);
    }
  }

  static Future<String> getModel(AiProvider provider) async {
    final p = await SharedPreferences.getInstance();
    return switch (provider) {
      AiProvider.deepseek =>
        p.getString(_kDeepseekModel)?.trim().isNotEmpty == true
            ? p.getString(_kDeepseekModel)!.trim()
            : defaultDeepseekModel,
      AiProvider.doubao =>
        p.getString(_kDoubaoModel)?.trim().isNotEmpty == true
            ? p.getString(_kDoubaoModel)!.trim()
            : defaultDoubaoModel,
    };
  }

  static Future<void> setModel(AiProvider provider, String model) async {
    final p = await SharedPreferences.getInstance();
    final v = model.trim();
    switch (provider) {
      case AiProvider.deepseek:
        await p.setString(_kDeepseekModel, v);
      case AiProvider.doubao:
        await p.setString(_kDoubaoModel, v);
    }
  }

  static Future<String> getDoubaoBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kDoubaoBase)?.trim();
    if (v == null || v.isEmpty) return defaultDoubaoBase;
    return v.replaceAll(RegExp(r'/+$'), '');
  }

  static Future<void> setDoubaoBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDoubaoBase, url.trim());
  }

  static Future<bool> hasAnyKey() async {
    final d = await getApiKey(AiProvider.deepseek);
    final b = await getApiKey(AiProvider.doubao);
    return d.isNotEmpty || b.isNotEmpty;
  }
}
