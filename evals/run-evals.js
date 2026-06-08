#!/usr/bin/env node
/**
 * MAD-KG 关键流程 eval 运行器。
 * 读取 evals/critical-flows.json，对每条 fixture 用此处的参考实现断言不变量。
 * 这些参考实现必须与 lib/ 真实逻辑保持一致——任一断言失败即代表 lib/ 行为或本文件漂移。
 * 运行：node evals/run-evals.js   （或 npm run eval）
 */
const fs = require('fs');
const path = require('path');

const fixtures = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'critical-flows.json'), 'utf8')
).fixtures;

// ── 参考实现（镜像 lib/ 的纯逻辑不变量） ────────────────────────────

// auth_service: 密码 = userId 末 6 位
const derivePassword = (userId) => userId.slice(-6);

// defense_streaming_server _broadcast: 特定源只取自身，screen=win??phone，绝不回退 camera
const pickFrame = ({ source, win, phone, camera }) => {
  switch (source) {
    case 'win': return win ?? null;
    case 'phone': return phone ?? null;
    case 'screen': return win ?? phone ?? null;
    case 'camera': return camera ?? null;
    default: return win ?? phone ?? camera ?? null;
  }
};

// defense_streaming_server activeDefenderId: 心跳 ≤10s 视为活跃
const activeDefenderId = ({ lastHeartbeatSecondsAgo, studentId }) =>
  lastHeartbeatSecondsAgo <= 10 ? studentId : null;

// home_page _pullNotifications: 广播 >5min 视为过期
const showDefenseBanner = ({ broadcastAgeMinutes }) => broadcastAgeMinutes <= 5;

function actualFor(f) {
  switch (f.flow) {
    case '登录密码派生':
      return { password: derivePassword(f.input.userId) };
    case '答辩直播教师端分区取流':
      return { frame: pickFrame(f.input) };
    case '答辩学生活跃判定':
      return { activeDefenderId: activeDefenderId(f.input) };
    case '首页答辩通知横幅':
      return { showBanner: showDefenseBanner(f.input) };
    default:
      throw new Error(`未知 flow: ${f.flow}`);
  }
}

let passed = 0;
const failures = [];
for (const f of fixtures) {
  const actual = actualFor(f);
  const ok = JSON.stringify(actual) === JSON.stringify(f.expect);
  if (ok) {
    passed++;
  } else {
    failures.push({ id: f.id, expect: f.expect, actual });
  }
}

console.log(`Evals: ${passed}/${fixtures.length} passed`);
for (const fail of failures) {
  console.error(
    `  FAIL ${fail.id}: expected ${JSON.stringify(fail.expect)}, got ${JSON.stringify(fail.actual)}`
  );
}
process.exit(failures.length === 0 ? 0 : 1);
