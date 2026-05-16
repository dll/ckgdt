/// AI 服务商预设信息
class ProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> models;
  final String description;
  final String? freeNote;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
    required this.description,
    this.freeNote,
  });
}

/// 内置默认 API Key 映射（开发版使用，正式发布时移除）
///
/// 格式: 'provider:model' => apiKey
/// 如果只有 'provider' 则适用于该 provider 的所有模型
const bool kShowApiKeyInput = bool.fromEnvironment(
  'SHOW_API_KEY_INPUT',
  defaultValue: false,
);

const Map<String, String> builtinApiKeys = {
  'deepseek': 'sk-717ef9146311424daa2fbead8ed4682b',
  'zhipu': '5dc44da8d9dd4c28bf38cde316950f1e.nNIf7AXWrJXIcSyQ',
  'zhipu:glm-4.6v': '20322a4a95bf4bd68161b1f705aa6603.yHEHABcNAcOWy8WH',
};

class AiConfigModel {
  final String provider;
  final String? apiKey;
  final String model;
  final String? baseUrl;
  final String? updatedAt;
  final double temperature;
  final int maxTokens;
  final int timeout;

  const AiConfigModel({
    this.provider = 'deepseek',
    this.apiKey,
    this.model = 'deepseek-v4-pro',
    this.baseUrl,
    this.updatedAt,
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.timeout = 60,
  });

  // ── 13 个服务商预设 ──────────────────────────────────────────────────────

  static const providers = <ProviderPreset>[
    // ── 国内 ──────────────────────────────────────────────────────────────
    ProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      models: ['deepseek-v4-pro', 'deepseek-chat', 'deepseek-reasoner'],
      description: 'DeepSeek 开放平台，新用户注册即有免费额度，推荐使用 deepseek-v4-pro 高性能旗舰版。',
      freeNote: '新用户有免费额度',
    ),
    ProviderPreset(
      id: 'zhipu',
      name: '智谱清言 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      models: ['glm-4-flash', 'glm-4', 'glm-4-plus', 'glm-4.6v'],
      description: '智谱 AI 开放平台，glm-4-flash 模型对所有用户永久免费，无需充值即可使用。glm-4.6v 为视觉多模态模型。',
      freeNote: 'glm-4-flash 永久免费',
    ),
    ProviderPreset(
      id: 'qwen',
      name: '通义千问',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: ['qwen-turbo', 'qwen-plus', 'qwen-max', 'qwen-long'],
      description: '阿里云通义千问大模型，DashScope 兼容 OpenAI 接口，qwen-turbo 性价比高。',
      freeNote: '新用户有免费额度',
    ),
    ProviderPreset(
      id: 'kimi',
      name: '月之暗面 Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
      description: 'Kimi 智能助手，支持超长上下文（128k），适合长文档分析和复杂推理。',
      freeNote: '新用户有免费额度',
    ),
    ProviderPreset(
      id: 'doubao',
      name: '豆包',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      models: ['doubao-pro-4k', 'doubao-pro-32k', 'doubao-lite-4k'],
      description: '字节跳动豆包大模型，火山引擎 API，响应速度快，适合日常对话。',
    ),
    ProviderPreset(
      id: 'spark',
      name: '讯飞星火',
      baseUrl: 'https://spark-api-open.xf-yun.com/v1',
      models: ['generalv3.5', 'generalv3', '4.0Ultra'],
      description: '科大讯飞星火认知大模型，中文理解能力强，支持多轮对话。',
      freeNote: '有免费调用额度',
    ),
    ProviderPreset(
      id: 'hunyuan',
      name: '腾讯混元',
      baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
      models: ['hunyuan-lite', 'hunyuan-standard', 'hunyuan-pro'],
      description: '腾讯混元大模型，hunyuan-lite 免费使用，适合轻量级任务。',
      freeNote: 'hunyuan-lite 免费',
    ),

    // ── 国际 ──────────────────────────────────────────────────────────────
    ProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'],
      description: 'OpenAI GPT 系列模型，全球领先的大语言模型，需要海外网络环境。',
    ),
    ProviderPreset(
      id: 'openrouter',
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      models: [
        'anthropic/claude-opus-4-6',
        'anthropic/claude-sonnet-4-6',
        'anthropic/claude-3.5-sonnet',
        'google/gemini-2.0-flash-001',
        'openai/gpt-4o',
        'deepseek/deepseek-v4-pro',
      ],
      description: 'OpenRouter 聚合代理，一个 API Key 访问所有主流大模型（Claude/GPT/Gemini/DeepSeek等），推荐课件工坊使用 Claude Opus 生成高质量内容。',
      freeNote: '部分模型有免费额度',
    ),
    ProviderPreset(
      id: 'claude',
      name: 'Anthropic Claude',
      baseUrl: 'https://api.anthropic.com/v1',
      models: ['claude-sonnet-4-20250514', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'],
      description: 'Anthropic Claude 系列模型，擅长长文本分析和代码生成，需要海外网络环境。',
    ),
    ProviderPreset(
      id: 'gemini',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      models: ['gemini-2.0-flash', 'gemini-2.0-pro', 'gemini-1.5-flash'],
      description: 'Google Gemini 系列模型，使用 OpenAI 兼容接口，需要海外网络环境。',
    ),

    // ── 本地 ──────────────────────────────────────────────────────────────
    ProviderPreset(
      id: 'ollama',
      name: 'Ollama',
      baseUrl: 'http://localhost:11434/v1',
      models: ['llama3', 'qwen2', 'gemma2', 'mistral', 'codellama'],
      description: '本地部署 Ollama，支持多种开源模型，完全离线运行，无需 API Key。',
      freeNote: '本地免费',
    ),
    ProviderPreset(
      id: 'lmstudio',
      name: 'LM Studio',
      baseUrl: 'http://localhost:1234/v1',
      models: ['local-model'],
      description: '本地部署 LM Studio，图形化管理本地模型，兼容 OpenAI 接口。',
      freeNote: '本地免费',
    ),
    ProviderPreset(
      id: 'custom',
      name: '自定义服务',
      baseUrl: '',
      models: [],
      description: '自定义 OpenAI 兼容接口，适用于私有部署或第三方代理服务。',
    ),
  ];

  // ── 兼容旧代码的静态常量 ──────────────────────────────────────────────────

  static const deepseekDefaultUrl = 'https://api.deepseek.com';
  static const zhipuDefaultUrl = 'https://open.bigmodel.cn/api/paas/v4';

  // ── 派生属性 ──────────────────────────────────────────────────────────────

  /// 查找当前 provider 对应的预设
  ProviderPreset? get providerPreset {
    try {
      return providers.firstWhere((p) => p.id == provider);
    } catch (_) {
      return null;
    }
  }

  /// 有效的 API Key：优先用户自定义 → 内置模型特定 Key → 内置通用 Key
  String? get effectiveApiKey {
    // 用户已填写则优先使用
    if (apiKey != null && apiKey!.isNotEmpty) {
      // 检查是否有模型特定的内置 Key（如 zhipu:glm-4.6v）
      final modelSpecificKey = builtinApiKeys['$provider:$model'];
      if (modelSpecificKey != null) {
        // 如果用户填的就是该 provider 的通用 Key，且当前模型有专用 Key，则用专用 Key
        final genericKey = builtinApiKeys[provider];
        if (genericKey != null && apiKey == genericKey) {
          return modelSpecificKey;
        }
      }
      return apiKey;
    }
    // 检查模型特定内置 Key
    final modelKey = builtinApiKeys['$provider:$model'];
    if (modelKey != null) return modelKey;
    // 检查通用内置 Key
    return builtinApiKeys[provider];
  }

  /// 有效的 Base URL：优先用户自定义 → 预设默认 → DeepSeek 兜底
  String get effectiveBaseUrl {
    if (baseUrl != null && baseUrl!.isNotEmpty) return baseUrl!;
    final preset = providerPreset;
    if (preset != null && preset.baseUrl.isNotEmpty) return preset.baseUrl;
    return deepseekDefaultUrl;
  }

  /// 服务商显示名称
  String get providerLabel {
    final preset = providerPreset;
    return preset?.name ?? provider;
  }

  // ── 序列化 ────────────────────────────────────────────────────────────────

  factory AiConfigModel.fromMap(Map<String, dynamic> map) => AiConfigModel(
        provider: map['provider'] as String? ?? 'deepseek',
        apiKey: map['api_key'] as String?,
        model: map['model'] as String? ?? 'deepseek-v4-pro',
        baseUrl: map['base_url'] as String?,
        updatedAt: map['updated_at'] as String?,
        temperature: (map['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: (map['max_tokens'] as int?) ?? 2048,
        timeout: (map['timeout'] as int?) ?? 60,
      );

  Map<String, dynamic> toMap() => {
        'id': 1,
        'provider': provider,
        'api_key': apiKey,
        'model': model,
        'base_url': baseUrl,
        'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
        'temperature': temperature,
        'max_tokens': maxTokens,
        'timeout': timeout,
      };

  AiConfigModel copyWith({
    String? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
    double? temperature,
    int? maxTokens,
    int? timeout,
  }) =>
      AiConfigModel(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        timeout: timeout ?? this.timeout,
        updatedAt: DateTime.now().toIso8601String(),
      );
}
