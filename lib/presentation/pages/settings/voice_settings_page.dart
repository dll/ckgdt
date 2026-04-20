import 'package:flutter/material.dart';
import '../../../services/settings_service.dart';
import '../../../services/voice_service.dart';

/// 讯飞语音配置页面
///
/// 配置讯飞开放平台的 AppID、APIKey、APISecret，
/// 用于语音听写（语音转文字）功能。
class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key});

  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
  final _appIdController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();

  bool _obscureKey = true;
  bool _obscureSecret = true;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final appId = await SettingsService.getXunfeiAppId();
    final apiKey = await SettingsService.getXunfeiApiKey();
    final apiSecret = await SettingsService.getXunfeiApiSecret();
    _appIdController.text = appId;
    _apiKeyController.text = apiKey;
    _apiSecretController.text = apiSecret;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final appId = _appIdController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (appId.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写所有必填字段'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    await SettingsService.setXunfeiAppId(appId);
    await SettingsService.setXunfeiApiKey(apiKey);
    await SettingsService.setXunfeiApiSecret(apiSecret);

    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('讯飞语音配置已保存')),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _testVoice() async {
    // 先保存
    await SettingsService.setXunfeiAppId(_appIdController.text.trim());
    await SettingsService.setXunfeiApiKey(_apiKeyController.text.trim());
    await SettingsService.setXunfeiApiSecret(_apiSecretController.text.trim());

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final voiceService = VoiceService();
    String? result;
    bool success = false;

    voiceService.onResult = (text) {
      result = text;
    };
    voiceService.onComplete = (text) {
      result = text;
      success = true;
    };
    voiceService.onError = (error) {
      result = error;
      success = false;
    };

    final started = await voiceService.startListening();
    if (!started) {
      setState(() {
        _testing = false;
        _testResult = result ?? '启动失败，请检查配置和麦克风权限';
        _testSuccess = false;
      });
      return;
    }

    // 录 3 秒后停止
    await Future.delayed(const Duration(seconds: 3));
    await voiceService.stopListening();

    // 等待结果
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _testing = false;
        if (success || (result != null && result!.isNotEmpty)) {
          _testResult = '识别成功: "${result ?? ""}"';
          _testSuccess = true;
        } else {
          _testResult = result ?? '未识别到语音内容（请说话后重试）';
          _testSuccess = result == null || !result!.contains('错误');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('讯飞语音设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('讯飞语音设置'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 介绍卡片 ──────────────────────────────────────────────
            Card(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      primary.withValues(alpha: 0.1),
                      primary.withValues(alpha: 0.03),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mic, color: primary, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          '讯飞语音听写',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '使用讯飞开放平台的语音听写 (IAT) 服务，'
                      '支持语音输入学号、语音导航等功能。',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {},
                      child: Text(
                        '前往 console.xfyun.cn 创建应用并获取密钥',
                        style: TextStyle(
                          fontSize: 12,
                          color: primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── AppID ─────────────────────────────────────────────────
            TextFormField(
              controller: _appIdController,
              decoration: InputDecoration(
                labelText: 'AppID *',
                hintText: '在控制台 → 我的应用中获取',
                prefixIcon: const Icon(Icons.apps),
                border: const OutlineInputBorder(),
                helperText: '讯飞开放平台应用 ID',
                helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            const SizedBox(height: 16),

            // ── APIKey ────────────────────────────────────────────────
            TextFormField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'APIKey *',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── APISecret ────────────────────────────────────────────
            TextFormField(
              controller: _apiSecretController,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                labelText: 'APISecret *',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureSecret
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── 测试结果 ──────────────────────────────────────────────
            if (_testResult != null)
              Card(
                color: _testSuccess
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess ? Icons.check_circle : Icons.error,
                        color: _testSuccess ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _testSuccess
                                ? Colors.green[800]
                                : Colors.red[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ── 操作按钮 ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testVoice,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mic),
                    label: Text(_testing ? '录音中...(3秒)' : '测试语音'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: const Text('保存配置'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 使用说明 ──────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('使用说明',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildStep(
                        '1', '注册讯飞开放平台账号', 'console.xfyun.cn'),
                    _buildStep('2', '创建应用', '获取 AppID'),
                    _buildStep('3', '开通语音听写服务',
                        '免费版支持 500次/天'),
                    _buildStep('4', '填入上方参数并保存', '测试通过即可使用'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '语音功能：登录页语音输入学号、首页语音导航、'
                              '搜索语音输入等',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            child: Text(num,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(desc,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
