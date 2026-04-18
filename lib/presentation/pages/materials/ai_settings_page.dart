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

  // 新增参数
  double _temperature = 0.7;
  int _maxTokens = 2048;
  int _timeout = 60;

  final AiConfigDao _configDao = AiConfigDao();

  // ── 服务商分组 ────────────────────────────────────────────────────────────

  static const _domesticIds = [
    'deepseek', 'zhipu', 'qwen', 'kimi', 'doubao', 'spark', 'hunyuan',
  ];
  static const _internationalIds = ['openai', 'claude', 'gemini'];
  static const _localIds = ['ollama', 'lmstudio', 'custom'];

  /// 当前选中的预设
  ProviderPreset? get _currentPreset {
    try {
      return AiConfigModel.providers.firstWhere((p) => p.id == _provider);
    } catch (_) {
      return null;
    }
  }

  /// 当前预设的模型列表
  List<String> get _presetModels => _currentPreset?.models ?? [];

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
        _temperature = config.temperature;
        _maxTokens = config.maxTokens;
        _timeout = config.timeout;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── 切换服务商 ────────────────────────────────────────────────────────────

  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    final preset = AiConfigModel.providers.firstWhere(
      (p) => p.id == provider,
      orElse: () => AiConfigModel.providers.first,
    );
    setState(() {
      _provider = provider;
      _testResult = null;
      // 自动填入该服务商默认模型
      _modelController.text = preset.models.isNotEmpty ? preset.models.first : '';
      // 自动填入默认地址
      _baseUrlController.text = preset.baseUrl;
    });
  }

  // ── 测试连接 ──────────────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    // 本地服务商不需要 API Key
    final isLocal = _localIds.contains(_provider);
    // 检查是否有内置 Key
    final hasBuiltinKey = builtinApiKeys.containsKey(_provider) ||
        builtinApiKeys.containsKey('$_provider:${_modelController.text.trim()}');
    if (!isLocal && !hasBuiltinKey && apiKey.isEmpty) {
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
        _testResult = ok
            ? '✅ 连接成功！API Key 有效，模型响应正常。'
            : '❌ 连接失败，请检查 API Key 和网络。';
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
    final preset = _currentPreset;
    final defaultModel = preset != null && preset.models.isNotEmpty
        ? preset.models.first
        : 'deepseek-chat';

    final config = AiConfigModel(
      provider: _provider,
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? defaultModel
          : _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? null
          : _baseUrlController.text.trim(),
      temperature: _temperature,
      maxTokens: _maxTokens,
      timeout: _timeout,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  // ── 服务商选择 ─────────────────────────────────────────
                  _sectionTitle('服务商'),
                  const SizedBox(height: 10),
                  _buildProviderDropdown(primary, isDark),
                  const SizedBox(height: 16),

                  // ── 服务商信息卡片 ─────────────────────────────────────
                  _buildInfoCard(primary, gradient),
                  const SizedBox(height: 20),

                  // ── API Key（开发版隐藏，正式版显示）─────────────────
                  if (kShowApiKeyInput) ...[
                    _sectionTitle('API Key'),
                    const SizedBox(height: 6),
                    _buildApiKeyHint(primary),
                    const SizedBox(height: 8),
                    _buildApiKeyField(),
                    const SizedBox(height: 20),
                  ] else ...[
                    _buildBuiltinKeyBanner(primary),
                    const SizedBox(height: 20),
                  ],

                  // ── 模型选择 ───────────────────────────────────────────
                  _sectionTitle('模型'),
                  const SizedBox(height: 8),
                  _buildModelField(primary),
                  const SizedBox(height: 10),
                  if (_presetModels.isNotEmpty) ...[
                    _buildModelChips(primary),
                    const SizedBox(height: 20),
                  ],

                  // ── 高级设置（折叠）────────────────────────────────────
                  _buildAdvancedSection(primary, isDark),
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

  // ── 服务商下拉选择（分组）──────────────────────────────────────────────────

  Widget _buildProviderDropdown(Color primary, bool isDark) {
    return DropdownButtonFormField<String>(
      value: _provider,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.cloud_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: [
        // ── 国内服务商 ──
        _buildGroupHeader('国内服务商'),
        ..._buildProviderItems(_domesticIds),
        // ── 国际服务商 ──
        _buildGroupHeader('国际服务商'),
        ..._buildProviderItems(_internationalIds),
        // ── 本地部署 ──
        _buildGroupHeader('本地部署'),
        ..._buildProviderItems(_localIds),
      ],
      onChanged: _onProviderChanged,
      selectedItemBuilder: (context) {
        // 构建所有项（包括分组头）的选中态显示
        final allItems = <Widget>[];
        // 国内
        allItems.add(const SizedBox.shrink()); // 分组头占位
        for (final id in _domesticIds) {
          final preset = AiConfigModel.providers.firstWhere((p) => p.id == id);
          allItems.add(Text(preset.name));
        }
        // 国际
        allItems.add(const SizedBox.shrink());
        for (final id in _internationalIds) {
          final preset = AiConfigModel.providers.firstWhere((p) => p.id == id);
          allItems.add(Text(preset.name));
        }
        // 本地
        allItems.add(const SizedBox.shrink());
        for (final id in _localIds) {
          final preset = AiConfigModel.providers.firstWhere((p) => p.id == id);
          allItems.add(Text(preset.name));
        }
        return allItems;
      },
    );
  }

  DropdownMenuItem<String> _buildGroupHeader(String label) {
    return DropdownMenuItem<String>(
      enabled: false,
      value: null,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildProviderItems(List<String> ids) {
    return ids.map((id) {
      final preset = AiConfigModel.providers.firstWhere((p) => p.id == id);
      return DropdownMenuItem<String>(
        value: id,
        child: Row(
          children: [
            Expanded(
              child: Text(
                preset.name,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (preset.freeNote != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  preset.freeNote!,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  // ── 服务商信息卡片 ────────────────────────────────────────────────────────

  Widget _buildInfoCard(Color primary, LinearGradient gradient) {
    final preset = _currentPreset;
    if (preset == null) return const SizedBox.shrink();

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
                Expanded(
                  child: Text(
                    preset.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (preset.freeNote != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      preset.freeNote!,
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
              preset.description,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            if (preset.baseUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.link, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      preset.baseUrl,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 内置 Key 提示横幅 ────────────────────────────────────────────────────

  Widget _buildBuiltinKeyBanner(Color primary) {
    final hasKey = builtinApiKeys.containsKey(_provider) ||
        builtinApiKeys.containsKey('$_provider:${_modelController.text.trim()}');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasKey
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasKey
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasKey ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: hasKey ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasKey
                  ? '已内置 API Key，无需配置即可使用'
                  : '该服务商暂无内置 Key，请联系管理员',
              style: TextStyle(
                fontSize: 13,
                color: hasKey ? Colors.green.shade700 : Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── API Key 提示 ──────────────────────────────────────────────────────────

  Widget _buildApiKeyHint(Color primary) {
    final isLocal = _localIds.contains(_provider);
    final hintText = isLocal
        ? '本地部署无需 API Key，可留空'
        : '前往服务商官网申请 API Key';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            isLocal ? Icons.info_outline : Icons.open_in_new,
            size: 14,
            color: primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hintText,
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
            _obscureKey
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
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
    final preset = _currentPreset;
    final hintModel = preset != null && preset.models.isNotEmpty
        ? preset.models.first
        : 'model-name';

    return TextFormField(
      controller: _modelController,
      decoration: InputDecoration(
        hintText: hintModel,
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
      children: _presetModels.map((m) {
        final selected = _modelController.text.trim() == m;
        // 标记免费模型
        final isFree = m == 'glm-4-flash' ||
            m == 'hunyuan-lite' ||
            _localIds.contains(_provider);
        return GestureDetector(
          onTap: () => setState(() => _modelController.text = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? primary : primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? primary : primary.withValues(alpha: 0.25),
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isFree) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.green.withValues(alpha: 0.15),
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

  Widget _buildAdvancedSection(Color primary, bool isDark) {
    final preset = _currentPreset;
    final defaultUrl = preset?.baseUrl ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折叠标题
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
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
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
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
                      // ── 接口地址 ──────────────────────────────────────
                      if (defaultUrl.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            border: Border.all(color: Colors.amber.shade200),
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
                                  '默认地址：$defaultUrl\n留空则使用默认地址，通常无需修改。',
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
                          hintText: defaultUrl.isNotEmpty
                              ? defaultUrl
                              : 'https://your-api-url.com/v1',
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
                                  onPressed: () => setState(
                                      () => _baseUrlController.clear()),
                                )
                              : null,
                        ),
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 20),

                      // ── Temperature ───────────────────────────────────
                      _sectionTitle('Temperature（创造性）'),
                      const SizedBox(height: 4),
                      _buildSliderRow(
                        value: _temperature,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        label: _temperature.toStringAsFixed(1),
                        onChanged: (v) =>
                            setState(() => _temperature = v),
                        primary: primary,
                        hint: '值越高回复越有创造性，越低越稳定',
                      ),

                      const SizedBox(height: 16),

                      // ── Max Tokens ────────────────────────────────────
                      _sectionTitle('Max Tokens（最大输出长度）'),
                      const SizedBox(height: 4),
                      _buildSliderRow(
                        value: _maxTokens.toDouble(),
                        min: 256,
                        max: 8192,
                        divisions: 31, // (8192-256)/256 ≈ 31
                        label: '$_maxTokens',
                        onChanged: (v) =>
                            setState(() => _maxTokens = v.round()),
                        primary: primary,
                        hint: '单次回复的最大 token 数',
                      ),

                      const SizedBox(height: 16),

                      // ── Timeout ───────────────────────────────────────
                      _sectionTitle('Timeout（超时时间）'),
                      const SizedBox(height: 4),
                      _buildSliderRow(
                        value: _timeout.toDouble(),
                        min: 15,
                        max: 120,
                        divisions: 21, // (120-15)/5 = 21
                        label: '$_timeout 秒',
                        onChanged: (v) =>
                            setState(() => _timeout = v.round()),
                        primary: primary,
                        hint: '请求超时时间（秒）',
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── 滑块行 ────────────────────────────────────────────────────────────────

  Widget _buildSliderRow({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required Color primary,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: primary,
                  inactiveTrackColor: primary.withValues(alpha: 0.15),
                  thumbColor: primary,
                  overlayColor: primary.withValues(alpha: 0.12),
                  valueIndicatorColor: primary,
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: label,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              hint,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
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
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: primary),
            )
          : const Icon(Icons.network_check_outlined),
      label: Text(_testing ? '测试中…' : '测试连接'),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        color: _testSuccess ? Colors.green.shade50 : Colors.red.shade50,
        border: Border.all(
          color:
              _testSuccess ? Colors.green.shade300 : Colors.red.shade300,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _testSuccess ? Icons.check_circle : Icons.error_outline,
            color:
                _testSuccess ? Colors.green.shade600 : Colors.red.shade600,
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
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
