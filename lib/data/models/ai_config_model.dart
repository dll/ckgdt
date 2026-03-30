class AiConfigModel {
  final String provider; // 'deepseek', 'zhipu'
  final String? apiKey;
  final String model;
  final String? baseUrl;
  final String? updatedAt;

  const AiConfigModel({
    this.provider = 'deepseek',
    this.apiKey,
    this.model = 'deepseek-chat',
    this.baseUrl,
    this.updatedAt,
  });

  static const deepseekDefaultUrl = 'https://api.deepseek.com';
  static const zhipuDefaultUrl = 'https://open.bigmodel.cn/api/paas/v4';

  String get effectiveBaseUrl {
    if (baseUrl != null && baseUrl!.isNotEmpty) return baseUrl!;
    return provider == 'zhipu' ? zhipuDefaultUrl : deepseekDefaultUrl;
  }

  String get providerLabel => provider == 'zhipu' ? '智谱清言 GLM' : 'DeepSeek';

  factory AiConfigModel.fromMap(Map<String, dynamic> map) => AiConfigModel(
        provider: map['provider'] as String? ?? 'deepseek',
        apiKey: map['api_key'] as String?,
        model: map['model'] as String? ?? 'deepseek-chat',
        baseUrl: map['base_url'] as String?,
        updatedAt: map['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': 1,
        'provider': provider,
        'api_key': apiKey,
        'model': model,
        'base_url': baseUrl,
        'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      };

  AiConfigModel copyWith({
    String? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) =>
      AiConfigModel(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        updatedAt: DateTime.now().toIso8601String(),
      );
}
