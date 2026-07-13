import 'package:flutter/material.dart';
import '../../../services/agent/agent_registry.dart';
import '../../../services/agent/agent_model.dart';
import '../../../services/auth_service.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../core/design/noir_components.dart';
import '../../widgets/agent_chat_overlay.dart';

List<Color> _cardColor(String id) {
  const map = {
    'voice': [0xFF667eea, 0xFF764ba2],
    'graph': [0xFF4facfe, 0xFF00f2fe],
    'quiz': [0xFFf093fb, 0xFFf5576c],
    'repo': [0xFF43e97b, 0xFF38f9d7],
    'assessment': [0xFFfa709a, 0xFFfee140],
    'lab': [0xFFa18cd1, 0xFFfbc2eb],
    'works': [0xFF84fab0, 0xFF8fd3f4],
    'achievement': [0xFFf6d365, 0xFFfda085],
    'courseware': [0xFFa1c4fd, 0xFFc2e9fb],
    'tutor': [0xFF2d6a4f, 0xFF52b788],
    'doc_converter': [0xFFe0c3fc, 0xFF8ec5fc],
    'mobile_expert': [0xFFfccb90, 0xFFd57eeb],
    'ethics': [0xFF667eea, 0xFF43e97b],
    'safety': [0xFFf5576c, 0xFFf093fb],
    'archive': [0xFF8fd3f4, 0xFF84fab0],
    'grading': [0xFF764ba2, 0xFFa18cd1],
    'digital_twin': [0xFFc2e9fb, 0xFFa1c4fd],
    'case_demo': [0xFF2d6a4f, 0xFFf6d365],
    'courseware_workshop': [0xFF4facfe, 0xFF43e97b],
    'assistant': [0xFF667eea, 0xFF764ba2],
  };
  final c = map[id] ?? [0xFF667eea, 0xFF764ba2];
  return [Color(c[0]), Color(c[1])];
}

/// 智能体广场 — 列出所有智能体，显示使用指南，一键发起对话
class AgentDirectoryPage extends StatefulWidget {
  final String? initialAgentId;

  const AgentDirectoryPage({super.key, this.initialAgentId});

  @override
  State<AgentDirectoryPage> createState() => _AgentDirectoryPageState();

  static List<Color> _cardColor(String id) {
    const map = {
      'voice': [0xFF667eea, 0xFF764ba2],
      'graph': [0xFF4facfe, 0xFF00f2fe],
      'quiz': [0xFFf093fb, 0xFFf5576c],
      'repo': [0xFF43e97b, 0xFF38f9d7],
      'assessment': [0xFFfa709a, 0xFFfee140],
      'lab': [0xFFa18cd1, 0xFFfbc2eb],
      'works': [0xFF84fab0, 0xFF8fd3f4],
      'achievement': [0xFFf6d365, 0xFFfda085],
      'courseware': [0xFFa1c4fd, 0xFFc2e9fb],
      'tutor': [0xFF2d6a4f, 0xFF52b788],
      'doc_converter': [0xFFe0c3fc, 0xFF8ec5fc],
      'mobile_expert': [0xFFfccb90, 0xFFd57eeb],
      'ethics': [0xFF667eea, 0xFF43e97b],
      'safety': [0xFFf5576c, 0xFFf093fb],
      'archive': [0xFF8fd3f4, 0xFF84fab0],
      'grading': [0xFF764ba2, 0xFFa18cd1],
      'digital_twin': [0xFFc2e9fb, 0xFFa1c4fd],
      'case_demo': [0xFF2d6a4f, 0xFFf6d365],
      'courseware_workshop': [0xFF4facfe, 0xFF43e97b],
      'assistant': [0xFF667eea, 0xFF764ba2],
    };
    final c = map[id] ?? [0xFF667eea, 0xFF764ba2];
    return [Color(c[0]), Color(c[1])];
  }
}

class _AgentDirectoryPageState extends State<AgentDirectoryPage> {
  final _registry = AgentRegistry.instance;
  List<AgentConfig> _configs = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  void _loadAgents() {
    final role = AuthService().currentUser?.role ?? 'student';
    setState(() => _configs = _registry.configsForRole(role));
  }

  List<AgentConfig> get _filteredConfigs {
    if (_searchQuery.isEmpty) return _configs;
    final q = _searchQuery.toLowerCase();
    return _configs.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.capabilities.any((cap) => cap.toLowerCase().contains(q)) ||
          c.keywords.any((kw) => kw.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoirTokens.ink,
      appBar: AppBar(
        backgroundColor: NoirTokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: NoirTokens.paper),
        title: const Text('智能体广场',
            style: TextStyle(color: NoirTokens.paper)),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _filteredConfigs.isEmpty
                ? Center(
                    child: Text('无匹配智能体',
                        style: TextStyle(color: NoirTokens.inkAlpha(0.5))),
                  )
                : LayoutBuilder(builder: (context, constraints) {
                    final cols = constraints.maxWidth > 900
                        ? 4
                        : constraints.maxWidth > 600
                            ? 3
                            : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: 0.85,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemCount: _filteredConfigs.length,
                      itemBuilder: (_, i) =>
                          _buildAgentCard(_filteredConfigs[i]),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: NoirTokens.paper, fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索智能体名称、能力或关键词…',
          hintStyle: TextStyle(color: NoirTokens.paper.withOpacity(0.4)),
          prefixIcon: Icon(Icons.search, color: NoirTokens.paper.withOpacity(0.6)),
          fillColor: NoirTokens.inkDeep,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NoirTokens.radius),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildAgentCard(AgentConfig config) {
    final colors = _cardColor(config.id);
    return NoirCard(
      padding: EdgeInsets.zero,
      onTap: () => _showAgentDetail(config),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors[0], colors[1]],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(NoirTokens.radius)),
              ),
              child: Center(
                child: Text(config.emoji, style: const TextStyle(fontSize: 40)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    config.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: NoirTokens.ink,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    config.description,
                    style: NoirTokens.muted(size: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (config.capabilities.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: config.capabilities.take(3).map((cap) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors[0].withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(cap,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: colors[0])),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAgentDetail(AgentConfig config) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
      ),
      builder: (ctx) => _AgentDetailSheet(config: config, onChat: () {
        Navigator.pop(ctx);
        AgentChatOverlay.show(context, agentId: config.id);
      }),
    );
  }
}

class _AgentDetailSheet extends StatelessWidget {
  final AgentConfig config;
  final VoidCallback onChat;

  const _AgentDetailSheet({required this.config, required this.onChat});

  @override
  Widget build(BuildContext context) {
    final colors = _cardColor(config.id);
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.85,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors[0], colors[1]],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(NoirTokens.radius),
                  ),
                  child: Center(
                    child: Text(config.emoji, style: const TextStyle(fontSize: 30)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(config.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800,
                              color: NoirTokens.ink)),
                      const SizedBox(height: 4),
                      Text(config.description,
                          style: NoirTokens.muted(size: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Capabilities
            if (config.capabilities.isNotEmpty) ...[
              _sectionHeader('能力标签'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 6,
                children: config.capabilities.map((cap) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors[0].withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(cap,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: colors[0])),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // Usage Steps
            if (config.usageSteps.isNotEmpty) ...[
              _sectionHeader('使用步骤'),
              const SizedBox(height: 8),
              ...config.usageSteps.asMap().entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: colors[0],
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.value,
                            style: const TextStyle(
                                fontSize: 13, height: 1.4,
                                color: NoirTokens.ink)),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],

            // Classic Cases
            if (config.classicCases.isNotEmpty) ...[
              _sectionHeader('经典案例'),
              const SizedBox(height: 8),
              ...config.classicCases.map((c) => _buildCaseTile(c)),
              const SizedBox(height: 24),
            ],

            // Start Chat Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text('与「${config.name}」对话'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors[0],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NoirTokens.radius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: _cardColor(config.id)[0]),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: NoirTokens.ink)),
      ],
    );
  }

  Widget _buildCaseTile(AgentCase c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: NoirTokens.inkAlpha(0.05),
        borderRadius: BorderRadius.circular(NoirTokens.radius),
        border: Border.all(color: NoirTokens.inkAlpha(0.08)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(c.title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: NoirTokens.ink)),
        subtitle: Text(c.userInput,
            style: TextStyle(fontSize: 11, color: NoirTokens.inkAlpha(0.5))),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(c.agentReply,
                style: const TextStyle(fontSize: 12, height: 1.4,
                    color: NoirTokens.ink)),
          ),
        ],
      ),
    );
  }
}
