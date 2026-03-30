import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../data/models/ai_config_model.dart';
import '../../../services/ai_service.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  // ── 控制器 ────────────────────────────────────────────────────────────────

  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ── 状态 ──────────────────────────────────────────────────────────────────

  String _provider = 'deepseek';
  bool _obscureKey = true;
  bool _showAdvanced = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  final AiConfigDao _configDao = AiConfigDao();

  // ── 快捷模型列表 ──────────────────────────────────────────────────────────

  static const _deepseekModels = ['deepseek-chat', 'deepseek-reasoner'];
  static const _zhipuModels = ['glm-4-flash', 'glm-4', 'glm-4-plus'];

  List<String> get _quickModels =>
      _provider == 'zhipu' ? _zhipuModels : _deepseekModels;

  // ── 服务商说明 ────────────────────────────────────────────────────────────

  static const _deepseekInfo = (
    url: 'https://platform.deepseek.com',
    desc: 'DeepSeek 开放平台，新用户注册即有免费额度，推荐使用 deepseek-chat 模型。',
    freeNote: '新用户有免费额度',
  );

  static const _zhipuInfo = (
    url: 'https://open.bigmodel.cn',
    desc: '智谱 AI 开放平台，glm-4-flash 模型对所有用户永久免费，无需充值即可使用。',
    freeNote: 'glm-4-flash 永久免费',
  );

  // ── 初始化 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _configDao.getConfig();
      if (!mounted) return;
      setState(() {
        _provider = config.provider;
        _apiKeyController.text = config.apiKey ?? '';
        _modelController.text = config.model;
        _baseUrlController.text = config.baseUrl ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── 切换服务商 ────────────────────────────────────────────────────────────

  void _onProviderChanged(String provider) {
    setState(() {
      _provider = provider;
      _testResult = null;
      // 自动填入该服务商默认模型
      _modelController.text =
          provider == 'zhipu' ? 'glm-4-flash' : 'deepseek-chat';
      // 清空自定义地址（使用默认）
      _baseUrlController.clear();
    });
  }

  // ── 测试连接 ──────────────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnack('请先输入 API Key');
      return;
    }

    // 临时保存当前配置再测试
    await _saveInternal(silent: true);

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final ok = await AiService().testConnection();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = ok;
        _testResult = ok ? '✅ 连接成功！API Key 有效，模型响应正常。' : '❌ 连接失败，请检查 API Key 和网络。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = '❌ 连接异常：$e';
      });
    }
  }

  // ── 保存配置 ──────────────────────────────────────────────────────────────

  Future<void> _saveInternal({bool silent = false}) async {
    final config = AiConfigModel(
      provider: _provider,
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? (_provider == 'zhipu' ? 'glm-4-flash' : 'deepseek-chat')
          : _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? null
          : _baseUrlController.text.trim(),
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _configDao.saveConfig(config);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await _saveInternal();
      if (!mounted) return;
      _showSnack('✅ 配置已保存', success: true);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade600 : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context).linearGradient;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 接口配置'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('保存',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── 顶部说明卡片 ───────────────────────────────────────
                  _buildInfoCard(primary, gradient),
                  const SizedBox(height: 20),

                  // ── 服务商选择 ─────────────────────────────────────────
                  _sectionTitle('服务商'),
                  const SizedBox(height: 10),
                  _buildProviderSelector(primary),
                  const SizedBox(height: 20),

                  // ── API Key ────────────────────────────────────────────
                  _sectionTitle('API Key'),
                  const SizedBox(height: 6),
                  _buildApiKeyHint(primary),
                  const SizedBox(height: 8),
                  _buildApiKeyField(),
                  const SizedBox(height: 20),

                  // ── 模型选择 ───────────────────────────────────────────
                  _sectionTitle('模型'),
                  const SizedBox(height: 8),
                  _buildModelField(primary),
                  const SizedBox(height: 10),
                  _buildModelChips(primary),
                  const SizedBox(height: 20),

                  // ── 高级设置（折叠）────────────────────────────────────
                  _buildAdvancedSection(primary),
                  const SizedBox(height: 24),

                  // ── 测试连接按钮 ────────────────────────────────────────
                  _buildTestButton(primary),

                  // ── 测试结果 ───────────────────────────────────────────
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    _buildTestResult(),
                  ],
                  const SizedBox(height: 24),

                  // ── 保存按钮 ───────────────────────────────────────────
                  _buildSaveButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── 顶部说明卡片 ──────────────────────────────────────────────────────────

  Widget _buildInfoCard(Color primary, LinearGradient gradient) {
    final info = _provider == 'zhipu' ? _zhipuInfo : _deepseekInfo;

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  _provider == 'zhipu' ? '智谱清言 GLM' : 'DeepSeek',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    info.freeNote,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              info.desc,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.link, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Text(
                  info.url,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 服务商 SegmentedButton ────────────────────────────────────────────────

  Widget _buildProviderSelector(Color primary) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'deepseek',
          label: Text('DeepSeek'),
          icon: Icon(Icons.rocket_launch_outlined, size: 18),
        ),
        ButtonSegment(
          value: 'zhipu',
          label: Text('智谱 GLM'),
          icon: Icon(Icons.psychology_outlined, size: 18),
        ),
      ],
      selected: {_provider},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) _onProviderChanged(selected.first);
      },
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: primary.withOpacity(0.12),
        selectedForegroundColor: primary,
      ),
    );
  }

  // ── API Key 提示 ──────────────────────────────────────────────────────────

  Widget _buildApiKeyHint(Color primary) {
    final info = _provider == 'zhipu' ? _zhipuInfo : _deepseekInfo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.open_in_new, size: 14, color: primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '前往 ${info.url} 申请 API Key',
              style: TextStyle(
                  fontSize: 12, color: primary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── API Key 输入框 ────────────────────────────────────────────────────────

  Widget _buildApiKeyField() {
    return TextFormField(
      controller: _apiKeyController,
      obscureText: _obscureKey,
      decoration: InputDecoration(
        hintText: 'sk-...',
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
          onPressed: () => setState(() => _obscureKey = !_obscureKey),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      // API Key 不强制校验，允许暂时为空
      validator: (_) => null,
    );
  }

  // ── 模型输入框 ────────────────────────────────────────────────────────────

  Widget _buildModelField(Color primary) {
    return TextFormField(
      controller: _modelController,
      decoration: InputDecoration(
        hintText: _provider == 'zhipu' ? 'glm-4-flash' : 'deepseek-chat',
        prefixIcon: const Icon(Icons.memory_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        helperText: '可手动输入任意模型名称',
        helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
      ),
    );
  }

  // ── 模型快捷 Chips ────────────────────────────────────────────────────────

  Widget _buildModelChips(Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _quickModels.map((m) {
        final selected = _modelController.text.trim() == m;
        final isFree = m == 'glm-4-flash';
        return GestureDetector(
          onTap: () => setState(() => _modelController.text = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? primary : primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? primary : primary.withOpacity(0.25),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : primary,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isFree) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withOpacity(0.25)
                          : Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '免费',
                      style: TextStyle(
                        fontSize: 10,
                        color: selected ? Colors.white : Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 高级设置（折叠）──────────────────────────────────────────────────────

  Widget _buildAdvancedSection(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折叠标题
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  '高级设置',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showAdvanced
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),

        // 折叠内容
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _showAdvanced
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 默认地址提示
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border:
                              Border.all(color: Colors.amber.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '默认地址：${_provider == 'zhipu' ? AiConfigModel.zhipuDefaultUrl : AiConfigModel.deepseekDefaultUrl}\n'
                                '留空则使用默认地址，通常无需修改。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _sectionTitle('自定义接口地址（可选）'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          hintText: _provider == 'zhipu'
                              ? AiConfigModel.zhipuDefaultUrl
                              : AiConfigModel.deepseekDefaultUrl,
                          prefixIcon: const Icon(Icons.link_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          helperText: '留空使用默认地址，代理部署时填写',
                          helperStyle: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                          suffixIcon: _baseUrlController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () =>
                                      setState(() => _baseUrlController.clear()),
                                )
                              : null,
                        ),
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── 测试连接按钮 ──────────────────────────────────────────────────────────

  Widget _buildTestButton(Color primary) {
    return OutlinedButton.icon(
      icon: _testing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: primary),
            )
          : const Icon(Icons.network_check_outlined),
      label: Text(_testing ? '测试中…' : '测试连接'),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(double.infinity, 50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _testing ? null : _testConnection,
    );
  }

  // ── 测试结果卡片 ──────────────────────────────────────────────────────────

  Widget _buildTestResult() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _testSuccess
            ? Colors.green.shade50
            : Colors.red.shade50,
        border: Border.all(
          color: _testSuccess
              ? Colors.green.shade300
              : Colors.red.shade300,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _testSuccess ? Icons.check_circle : Icons.error_outline,
            color: _testSuccess ? Colors.green.shade600 : Colors.red.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testResult ?? '',
              style: TextStyle(
                fontSize: 13,
                color: _testSuccess
                    ? Colors.green.shade800
                    : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 保存按钮 ──────────────────────────────────────────────────────────────

  Widget _buildSaveButton() {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save_outlined),
        label: Text(
          _saving ? '保存中…' : '保存配置',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _saving ? null : _save,
      ),
    );
  }

  // ── 辅助 ─────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}
