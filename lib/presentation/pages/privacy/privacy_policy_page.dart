import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../widgets/back_button_bar.dart';

/// 用户协议 + 隐私声明合并页（双 Tab 静态展示）。
///
/// 内容写在代码里（不读 assets）—— 这样 GitHub 公开仓库一目了然，
/// 评委 / 审计直接看到声明文本。修订时改 [version] 同步升号即可。
class PrivacyPolicyPage extends StatelessWidget {
  /// 0 = 用户协议；1 = 隐私声明
  final int initialTab;

  const PrivacyPolicyPage({super.key, this.initialTab = 0});

  /// 与代码内文本一致的修订号 — 用户在登录时如果同意的版本与此不一致，
  /// 应再次弹同意框（当前版本暂未做强制重弹，留作后续合规升级钩子）。
  static const String version = '2026-05-23';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: const Scaffold(
        appBar: BackButtonBar(
          title: '用户协议与隐私声明',
          bottom: TabBar(
            tabs: [
              Tab(text: '用户协议'),
              Tab(text: '隐私声明'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MarkdownPanel(content: _userAgreement),
            _MarkdownPanel(content: _privacyPolicy),
          ],
        ),
      ),
    );
  }
}

class _MarkdownPanel extends StatelessWidget {
  final String content;
  const _MarkdownPanel({required this.content});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      padding: const EdgeInsets.all(16),
      selectable: true,
      data: content,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 13, height: 1.6),
        listBullet: const TextStyle(fontSize: 13, height: 1.6),
      ),
    );
  }
}

const _userAgreement = '''
# 《CKGDT 课程知识图谱与数字孪生平台》用户协议

**版本：${PrivacyPolicyPage.version}**

## 一、协议范围

本协议适用于 CKGDT 课程知识图谱与数字孪生平台的所有终端用户，包括学生、教师、管理员。
登录使用本平台即视为同意本协议。

## 二、账号规则

1. 账号：使用所在学校提供的学号 / 工号。
2. 密码：默认为学号 / 工号末 6 位。该密码由系统统一生成，**当前版本不支持自助修改**。
3. 用户应妥善保管自己的账号密码，因密码泄露引起的损失由用户本人承担。

## 三、使用规范

用户在使用平台时不得：
- 上传违反法律法规的内容；
- 提交他人作品冒充自己作品（学术诚信）；
- 使用 AI 工具直接代写实验报告、考核报告并提交（系统会自动检测并标记 AI_SUSPECT）；
- 干扰其他用户的正常使用，包括但不限于恶意修改他人作品评分、删除他人提交内容；
- 利用平台漏洞进行未经授权的测试。

## 四、数据所有权

- 用户上传的实验报告、作品、答辩材料等所有原创内容，著作权归用户本人所有；
- 平台拥有为教学目的展示、批阅、统计这些内容的权利；
- 教师对作品的批阅评语属于教师作品，但与学生作品共同构成教学过程记录。

## 五、AI 辅助说明

- 平台内 18 个智能体由 LLM 服务提供商（DeepSeek / 智谱 GLM / 自部署 Ollama 等）驱动；
- AI 生成的内容仅作教学辅助，不代表平台官方意见；
- AI 批阅结果**仅供教师参考**，最终成绩以教师审核后为准。

## 六、争议解决

如有争议，应通过平台内"意见反馈"通道提交。涉及成绩异议的，按所在学校教学管理规定处理。

## 七、本协议解释

本协议由 CKGDT 项目组保留最终解释权，修订内容会通过"版本"字段告知用户。
''';

const _privacyPolicy = '''
# 《CKGDT 课程知识图谱与数字孪生平台》隐私声明

**版本：${PrivacyPolicyPage.version}**

## 一、收集的信息

平台仅收集与教学**直接相关**的信息：

1. 账号信息：学号 / 工号 / 姓名 / 班级 / 角色
2. 学习行为：测验答题、视频观看时长、知识点收藏、错题
3. 提交内容：实验报告、考核报告、作品、答辩材料、班级问答提问与回复
4. 教学批阅：教师对学生提交的评分、反馈、采纳记录
5. AI 调用日志：每次智能体对话的 prompt / 回复摘要 / 耗时 / 模型 / 用量（agent_call_logs 表）

平台**不收集**：
- 通讯录、短信、相册（除非用户主动选择上传作业附件）
- 位置信息
- 设备识别码 / IMEI
- 任何与课程教学无关的信息

## 二、信息用途

收集的信息仅用于：
- 学习过程记录与达成度分析
- AI 辅助教学（RAG 检索 / Agent 对话）
- 教学反思与课程改进
- 学术诚信审查

**不会**用于：
- 商业广告
- 转售给第三方
- 与其他课程平台共享

## 三、数据存储位置

1. **本地数据库（sqflite）**：存储在用户设备上，包括完整的学习行为与提交内容；
2. **Gitee 仓库（chzcldl/mad-kgdt 同步仓）**：用于无服务器跨设备同步，所有学生 / 教师共用一个仓库；
3. **AI 服务商服务器**：用户与智能体对话时，prompt 会被发送给 LLM 服务商（DeepSeek / 智谱 GLM 等）做推理，但仅作单次调用，不留作训练数据。

## 四、用户权利（请求方式见"我的数据"）

1. **查询权**：可随时查看自己上传的全部数据；
2. **导出权**：可一键导出自己的全部数据为 JSON 文件（个人中心 → 我的数据 → 导出）；
3. **删除权**：可一键清空本地数据（个人中心 → 我的数据 → 删除我的数据）；如需同步删除 Gitee 远程副本，请联系管理员（Gitee 仓库为教学过程档案，含教师批阅记录与班级问答历史，自助删除会影响他人）；
4. **更正权**：发现自己的成绩 / 评语错误时，可通过班级问答 / 反馈通道申请更正。

## 五、数据安全

- 平台所有用户共用同一个 Gitee 仓库 token（写在客户端代码中，作为"教学场景认证"），属于已知设计取舍 —— 牺牲了"恶意学生破坏他人数据"的强防护，换取了无服务器部署成本；如果对此设计不满，请勿在平台上传敏感个人信息（身份证 / 手机号 / 真实住址等）；
- 任何自动化的安全审查（safety agent）只读不写，不会代用户做销毁性操作；
- 教师批阅一旦核准入库，会通过 grading_results 表保留审计痕迹。

## 六、面向未成年人

如果你未满 18 岁，请在监护人指导下使用本平台，并在使用前与监护人共同阅读本声明。

## 七、联系方式

如对本声明有疑问，请通过平台内"意见反馈"通道提交，或联系所在学校教务处。
''';
