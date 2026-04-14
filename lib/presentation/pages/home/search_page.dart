import 'package:flutter/material.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/local/quiz_dao.dart';
import '../graph/graph_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  final _graphDao = GraphDao();
  final _quizDao = QuizDao();

  List<Map<String, dynamic>> _graphResults = [];
  List<Map<String, dynamic>> _questionResults = [];
  bool _isSearching = false;
  String _searchType = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _graphResults = [];
        _questionResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await Future.wait([
        _searchGraphs(query),
        _searchQuestions(query),
      ]);

      setState(() {
        _graphResults = results[0];
        _questionResults = results[1];
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  Future<List<Map<String, dynamic>>> _searchGraphs(String query) async {
    if (_searchType == 'questions') return [];
    final graphs = await _graphDao.getAllGraphs();
    return graphs.where((g) =>
      g.title.toLowerCase().contains(query.toLowerCase())
    ).map((g) => {'type': 'graph', 'data': g}).toList();
  }

  Future<List<Map<String, dynamic>>> _searchQuestions(String query) async {
    if (_searchType == 'graphs') return [];
    final questions = await _quizDao.getAllQuestions();
    return questions.where((q) =>
      q.question.toLowerCase().contains(query.toLowerCase())
    ).map((q) => {'type': 'question', 'data': q}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索知识点、题目...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _search,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索类型筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildFilterChip('全部', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('图谱', 'graphs'),
                const SizedBox(width: 8),
                _buildFilterChip('题目', 'questions'),
              ],
            ),
          ),

          // 搜索结果
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchController.text.isEmpty
                    ? _buildEmptyState()
                    : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _searchType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _searchType = value);
        _search(_searchController.text);
      },
      selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '输入关键词搜索',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '搜索图谱名称或测验题目',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final totalResults = _graphResults.length + _questionResults.length;

    if (totalResults == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未找到相关结果',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_graphResults.isNotEmpty) ...[
          _buildSectionHeader('图谱', _graphResults.length),
          ..._graphResults.map((r) => _buildGraphItem(r['data'])),
        ],
        if (_questionResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('题目', _questionResults.length),
          ..._questionResults.map((r) => _buildQuestionItem(r['data'])),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphItem(dynamic graph) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          child: Icon(Icons.account_tree, color: Colors.blue[700]),
        ),
        title: Text(graph.title),
        subtitle: Text('图谱'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GraphDetailPage(
                graphId: graph.id,
                graphTitle: graph.title,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionItem(dynamic question) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange[100],
          child: Icon(Icons.quiz, color: Colors.orange[700]),
        ),
        title: Text(
          question.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(question.source ?? '测验题'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          _showQuestionDetail(question);
        },
      ),
    );
  }

  void _showQuestionDetail(dynamic question) {
    final options = [
      'A. ${question.optionA}',
      'B. ${question.optionB}',
      'C. ${question.optionC}',
      'D. ${question.optionD}',
    ];
    final correctIdx = question.answerIndex as int;
    final correctLetter = ['A', 'B', 'C', 'D'][correctIdx];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (question.source != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF667eea).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(question.source!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF667eea))),
              ),
            Text(question.question,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, height: 1.5)),
            const SizedBox(height: 14),
            ...List.generate(4, (i) {
              final isCorrect = i == correctIdx;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? Colors.green.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCorrect
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(options[i],
                            style: TextStyle(
                                fontSize: 14,
                                color: isCorrect
                                    ? Colors.green[800]
                                    : Colors.black87))),
                    if (isCorrect)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Text('正确答案: $correctLetter',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
