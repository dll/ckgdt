part of '../git_repo_page.dart';

class _SubmissionGuidelinesTab extends StatelessWidget {
  const _SubmissionGuidelinesTab();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 重要提示横幅 ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.withValues(alpha: 0.15), Colors.red.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️ 命名规范必须严格遵守',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('不符合规范的仓库和分支将不会被系统识别和读取，'
                        '请在首次提交前仔细确认命名是否正确。',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 1. 仓库命名规范 ──
        _buildGuideCard(
          context,
          icon: Icons.folder_outlined,
          color: Colors.blue,
          title: '1. 仓库命名规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('仓库前缀', '必须以 cg1-、cg2- 或 cg3- 开头',
                Icons.check_circle, Colors.green),
            _buildRuleItem('命名格式', 'cg{组号}-{项目简称}',
                Icons.format_shapes, primary),
            const Divider(height: 20),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('cg1-sclspdi   (第1组-xxx项目)'),
            _buildCodeExample('cg2-sclspdi   (第2组-xxx项目)'),
            _buildCodeExample('cg3-ihftpdi   (第3组-xxx项目)'),
            const SizedBox(height: 8),
            const Text('❌ 错误示例（不会被读取）：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
            const SizedBox(height: 6),
            _buildCodeExample('cg1sclspdi    (缺少连字符 -)'),
            _buildCodeExample('CG1-project   (前缀必须小写)'),
            _buildCodeExample('project-cg1   (前缀位置不对)'),
            _buildCodeExample('my-project    (缺少 cg 前缀)'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 2. 分支命名规范 ──
        _buildGuideCard(
          context,
          icon: Icons.account_tree_outlined,
          color: Colors.green,
          title: '2. 分支命名规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('分支格式', 'feat-{姓名拼音首字母小写}',
                Icons.check_circle, Colors.green),
            _buildRuleItem('字母数量', '2~5 个小写字母',
                Icons.text_fields, primary),
            _buildRuleItem('用途', '每个学生在小组仓库中创建自己的分支',
                Icons.person, Colors.orange),
            const Divider(height: 20),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('feat-cjn     (陈佳宁 → cjn)'),
            _buildCodeExample('feat-ldl     (刘东良 → ldl)'),
            _buildCodeExample('feat-zwq     (张伟强 → zwq)'),
            _buildCodeExample('feat-cs      (陈帅 → cs)'),
            const SizedBox(height: 8),
            const Text('❌ 错误示例（不会被读取）：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
            const SizedBox(height: 6),
            _buildCodeExample('feat-CJN        (必须全小写)'),
            _buildCodeExample('feat-陈佳宁     (必须用拼音首字母)'),
            _buildCodeExample('feature-cjn     (前缀必须是 feat-)'),
            _buildCodeExample('cjn             (缺少 feat- 前缀)'),
            _buildCodeExample('feat-abcdef     (最多5个字母)'),
            _buildCodeExample('feat-a          (至少2个字母)'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 3. 提交（Commit）规范 ──
        _buildGuideCard(
          context,
          icon: Icons.commit,
          color: Colors.purple,
          title: '3. 提交消息规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('消息格式', '<类型>: <简短描述>',
                Icons.format_shapes, primary),
            const Divider(height: 20),
            const Text('提交类型：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildTypeChip('feat', '新功能 / 新增内容', Colors.green),
            _buildTypeChip('fix', '修复问题', Colors.red),
            _buildTypeChip('docs', '文档变更', Colors.blue),
            _buildTypeChip('style', '格式调整（不影响逻辑）', Colors.orange),
            _buildTypeChip('refactor', '代码重构', Colors.purple),
            _buildTypeChip('test', '测试相关', Colors.teal),
            const SizedBox(height: 10),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('feat: 完成实验一开发环境搭建'),
            _buildCodeExample('docs: 提交实验二实验报告'),
            _buildCodeExample('fix: 修复登录页面闪退'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 4. 实验提交规范 ──
        _buildGuideCard(
          context,
          icon: Icons.science_outlined,
          color: Colors.teal,
          title: '4. 实验提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('代码提交', '实验代码推送到个人分支（feat-xxx）',
                Icons.code, primary),
            _buildRuleItem('实验报告', '报告放在项目根目录 /docs/reports/ 下',
                Icons.description, Colors.blue),
            _buildRuleItem('文件命名', '实验报告命名为 实验X_姓名.md 或 .docx',
                Icons.drive_file_rename_outline, Colors.orange),
            const Divider(height: 20),
            const Text('目录结构参考：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'cg1-sclspdi/         ← 小组仓库\n'
              '├── docs/\n'
              '│   └── reports/\n'
              '│       ├── 实验一_姓名.md\n'
              '│       ├── 实验二_姓名.md\n'
              '│       └── ...\n'
              '├── src/              ← 项目源代码\n'
              '└── README.md'
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── 5. 考核项目规范 ──
        _buildGuideCard(
          context,
          icon: Icons.assignment_outlined,
          color: Colors.orange,
          title: '5. 考核项目提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('项目代码', '推送到个人分支',
                Icons.code, primary),
            _buildRuleItem('项目文档', '项目报告放在 /docs/ 目录下',
                Icons.folder_open, Colors.blue),
            _buildRuleItem('答辩材料', 'PPT 放在 /docs/defense/ 目录下',
                Icons.slideshow, Colors.green),
            _buildRuleItem('截止时间', '考核截止前必须完成所有推送',
                Icons.access_time, Colors.red),
          ],
        ),

        const SizedBox(height: 16),

        // ── 6. 作品提交规范 ──
        _buildGuideCard(
          context,
          icon: Icons.palette_outlined,
          color: Colors.indigo,
          title: '6. 作品提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('提交位置', '作品推送到个人分支的 /works/ 目录',
                Icons.folder_special, primary),
            _buildRuleItem('必须包含', 'README.md 说明文档（作品名称/截图/技术栈）',
                Icons.description, Colors.blue),
            _buildRuleItem('可选附件', '演示视频或截图放在 /works/assets/ 下',
                Icons.image, Colors.green),
          ],
        ),

        const SizedBox(height: 16),

        // ── 快速操作命令 ──
        _buildGuideCard(
          context,
          icon: Icons.terminal,
          color: Colors.grey,
          title: '常用 Git 命令',
          cardColor: cardColor,
          children: [
            const Text('首次克隆仓库并创建个人分支：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'git clone https://gitee.com/chzuczldl/cg1-sclspdi.git\n'
              'cd cg1-sclspdi\n'
              'git checkout -b feat-cjn\n'
              'git push -u origin feat-cjn'
            ),
            const SizedBox(height: 12),
            const Text('日常提交流程：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'git add .\n'
              'git commit -m "feat: 完成实验一开发环境搭建"\n'
              'git push'
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── 辅助构建方法 ────────────────────────────────────────────────────────

  static Widget _buildGuideCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget _buildRuleItem(
      String label, String desc, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: color),
                  ),
                  TextSpan(
                    text: desc,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCodeExample(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12, height: 1.4)),
      ),
    );
  }

  static Widget _buildCodeBlock(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFF89DDFF),
            height: 1.5),
      ),
    );
  }

  static Widget _buildTypeChip(String type, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(type,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4: Gitee 设置
// ══════════════════════════════════════════════════════════════════════════════

