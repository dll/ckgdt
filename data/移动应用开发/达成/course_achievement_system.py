import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import os
from datetime import datetime
import json
import sys

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei']
plt.rcParams['axes.unicode_minus'] = False

class CourseAchievementSystem:
    def __init__(self):
        # 课程目标权重
        self.objective_weights = {
            '课程目标1': 0.15,
            '课程目标2': 0.25,
            '课程目标3': 0.30,
            '课程目标4': 0.30
        }
        # 评估类型权重
        self.assessment_weights = {
            '平时': 0.20,
            '实验': 0.30,
            '期末': 0.50
        }
        self.students = []
        self.avg_achievements = {}
        self.weighted_achievement = 0
    
    def load_excel_data(self, excel_path):
        """加载Excel数据"""
        try:
            df = pd.read_excel(excel_path)
            return df
        except Exception as e:
            raise Exception(f"加载Excel文件失败: {str(e)}")
    
    def parse_excel_data(self, df):
        """解析Excel数据结构"""
        # 找到表头行
        header_row = -1
        for i, row in df.iterrows():
            if '课程目标' in str(row.iloc[0]):
                header_row = i
                break
        
        if header_row == -1:
            raise ValueError("未找到课程目标表头")
        
        # 提取数据行
        data_rows = []
        for i in range(header_row + 3, len(df)):
            row_data = []
            for col in df.columns:
                val = df.loc[i, col]
                if str(val) != 'nan':
                    row_data.append(val)
                else:
                    row_data.append('')
            if any(row_data):  # 跳过空行
                data_rows.append(row_data)
        
        # 提取学生数据
        students = []
        for row in data_rows:
            if len(row) >= 11:
                try:
                    student = {
                        '学号': str(row[0]),
                        '姓名': str(row[1]),
                        '目标1得分': float(row[2]) if row[2] else 0,
                        '目标1达成度': float(row[3]) if row[3] else 0,
                        '目标2得分': float(row[4]) if row[4] else 0,
                        '目标2达成度': float(row[5]) if row[5] else 0,
                        '目标3得分': float(row[6]) if row[6] else 0,
                        '目标3达成度': float(row[7]) if row[7] else 0,
                        '目标4得分': float(row[8]) if row[8] else 0,
                        '目标4达成度': float(row[9]) if row[9] else 0,
                        '总评得分': float(row[10]) if row[10] else 0
                    }
                    students.append(student)
                except Exception as e:
                    print(f"解析学生数据时出错: {e}")
                    continue
        
        return students
    
    def calculate_class_average(self, students):
        """计算班级平均达成度"""
        if not students:
            return {}
        
        avg_achievements = {
            '课程目标1': np.mean([s['目标1达成度'] for s in students]),
            '课程目标2': np.mean([s['目标2达成度'] for s in students]),
            '课程目标3': np.mean([s['目标3达成度'] for s in students]),
            '课程目标4': np.mean([s['目标4达成度'] for s in students]),
            '总评': np.mean([s['总评得分'] for s in students]) / 100
        }
        
        return avg_achievements
    
    def calculate_weighted_achievement(self, avg_achievements):
        """计算加权达成度"""
        weighted_achievement = 0
        for obj, weight in self.objective_weights.items():
            weighted_achievement += avg_achievements.get(obj, 0) * weight
        return weighted_achievement
    
    def generate_visualizations(self, avg_achievements, output_dir='./visualizations'):
        """生成可视化图表"""
        os.makedirs(output_dir, exist_ok=True)
        
        # 课程目标达成度柱状图
        objectives = list(avg_achievements.keys())[:-1]  # 排除总评
        achievements = [avg_achievements[obj] for obj in objectives]
        
        plt.figure(figsize=(10, 6))
        bars = plt.bar(objectives, achievements, color=['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4'])
        plt.title('课程目标达成度', fontsize=14, fontweight='bold')
        plt.ylabel('达成度', fontsize=12)
        plt.ylim(0, 1)
        
        # 添加数值标签
        for bar, val in zip(bars, achievements):
            plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                    f'{val:.4f}', ha='center', va='bottom', fontsize=10)
        
        plt.grid(axis='y', alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, '课程目标达成度柱状图.png'), dpi=300, bbox_inches='tight')
        plt.close()
        
        # 雷达图
        from math import pi
        
        plt.figure(figsize=(8, 8))
        ax = plt.subplot(111, polar=True)
        
        # 数据
        categories = objectives
        values = achievements
        values += values[:1]  # 闭合
        
        # 角度
        angles = [n / float(len(categories)) * 2 * pi for n in range(len(categories))]
        angles += angles[:1]
        
        ax.plot(angles, values, 'o-', linewidth=2, label='达成度', color='#FF6B6B')
        ax.fill(angles, values, alpha=0.25, color='#FF6B6B')
        ax.set_thetagrids([a * 180/pi for a in angles[:-1]], categories)
        ax.set_ylim(0, 1)
        plt.title('课程目标达成度雷达图', fontsize=14, fontweight='bold', pad=20)
        plt.legend(loc='upper right', bbox_to_anchor=(0.1, 0.1))
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, '课程目标达成度雷达图.png'), dpi=300, bbox_inches='tight')
        plt.close()
        
        # 学生个体达成度分布图
        student_achievements = []
        for student in self.students:
            student_achievements.append([
                student['目标1达成度'],
                student['目标2达成度'],
                student['目标3达成度'],
                student['目标4达成度']
            ])
        
        student_achievements = np.array(student_achievements)
        
        plt.figure(figsize=(12, 6))
        plt.boxplot(student_achievements, labels=['课程目标1', '课程目标2', '课程目标3', '课程目标4'])
        plt.title('学生个体达成度分布', fontsize=14, fontweight='bold')
        plt.ylabel('达成度', fontsize=12)
        plt.grid(axis='y', alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, '学生个体达成度分布图.png'), dpi=300, bbox_inches='tight')
        plt.close()
        
        return output_dir
    
    def generate_markdown_report(self, students, avg_achievements, weighted_achievement, output_file):
        """生成Markdown报告"""
        report_content = f"""# 软件23+6+《移动应用开发》课程达成度报告

**生成时间：** {datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')}

---

## 一、课程目标达成情况

### 1. 班级平均达成度

| 课程目标 | 达成度 | 权重 | 加权贡献 |
|---------|-------|------|---------|
| 课程目标1 | {avg_achievements.get('课程目标1', 0):.4f} | 0.15 | {avg_achievements.get('课程目标1', 0) * 0.15:.4f} |
| 课程目标2 | {avg_achievements.get('课程目标2', 0):.4f} | 0.25 | {avg_achievements.get('课程目标2', 0) * 0.25:.4f} |
| 课程目标3 | {avg_achievements.get('课程目标3', 0):.4f} | 0.30 | {avg_achievements.get('课程目标3', 0) * 0.30:.4f} |
| 课程目标4 | {avg_achievements.get('课程目标4', 0):.4f} | 0.30 | {avg_achievements.get('课程目标4', 0) * 0.30:.4f} |
| **加权总达成度** | **{weighted_achievement:.4f}** | **1.00** | **{weighted_achievement:.4f}** |

### 2. 学生个体达成情况

共有 **{len(students)}** 名学生参与评价。

#### 学生达成度统计

| 统计指标 | 课程目标1 | 课程目标2 | 课程目标3 | 课程目标4 |
|---------|----------|----------|----------|----------|
| 平均值 | {np.mean([s['目标1达成度'] for s in students]):.4f} | {np.mean([s['目标2达成度'] for s in students]):.4f} | {np.mean([s['目标3达成度'] for s in students]):.4f} | {np.mean([s['目标4达成度'] for s in students]):.4f} |
| 最大值 | {np.max([s['目标1达成度'] for s in students]):.4f} | {np.max([s['目标2达成度'] for s in students]):.4f} | {np.max([s['目标3达成度'] for s in students]):.4f} | {np.max([s['目标4达成度'] for s in students]):.4f} |
| 最小值 | {np.min([s['目标1达成度'] for s in students]):.4f} | {np.min([s['目标2达成度'] for s in students]):.4f} | {np.min([s['目标3达成度'] for s in students]):.4f} | {np.min([s['目标4达成度'] for s in students]):.4f} |
| 标准差 | {np.std([s['目标1达成度'] for s in students]):.4f} | {np.std([s['目标2达成度'] for s in students]):.4f} | {np.std([s['目标3达成度'] for s in students]):.4f} | {np.std([s['目标4达成度'] for s in students]):.4f} |

#### 达成度低于0.6的学生

"""
        
        # 添加达成度低于0.6的学生
        for obj in ['目标1', '目标2', '目标3', '目标4']:
            low_achievement_students = [s for s in students if s[f'{obj}达成度'] < 0.6]
            if low_achievement_students:
                report_content += f"\n**{obj}达成度低于0.6的学生（{len(low_achievement_students)}人）：**\n\n"
                for student in low_achievement_students:
                    report_content += f"- {student['学号']} {student['姓名']}: {student[f'{obj}达成度']:.4f}\n"
        
        report_content += """
---

## 二、达成度分析

### 1. 定量评价情况分析

#### 课程目标1分析
课程目标1主要考核学生掌握移动应用开发技术体系（原生/混合/跨平台）及主流平台特性，理解技术选型逻辑，熟悉跨平台开发框架和AI编程工具的基本使用。

**达成度：** {:.4f}

从达成度结果可以看出，学生在掌握移动应用开发技术体系和主流平台特性方面表现{("良好" if avg_achievements.get('课程目标1', 0) >= 0.7 else "一般")}。学生能够理解技术选型逻辑，熟悉跨平台开发框架和AI编程工具的基本使用。

#### 课程目标2分析
课程目标2主要考核学生运用跨平台开发框架及小程序技术，结合AI编程工具与后端API交互，设计实现跨平台应用，具备需求建模与创新应用能力。

**达成度：** {:.4f}

从达成度结果可以看出，学生在运用跨平台开发框架及小程序技术方面表现{("良好" if avg_achievements.get('课程目标2', 0) >= 0.7 else "一般")}。学生能够结合AI编程工具与后端API交互，设计实现跨平台应用。

#### 课程目标3分析
课程目标3主要考核学生调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力。

**达成度：** {:.4f}

从达成度结果可以看出，学生在调研对比多端开发方案和技术方案评估方面表现{("良好" if avg_achievements.get('课程目标3', 0) >= 0.7 else "一般")}。学生能够分析不同技术栈在跨设备适配场景中的优劣。

#### 课程目标4分析
课程目标4主要考核学生遵循软件工程规范，使用现代开发工具（含AI编程工具、Git版本控制）完成应用测试与优化，具备工程实践能力。

**达成度：** {:.4f}

从达成度结果可以看出，学生在使用现代开发工具和工程实践方面表现{("良好" if avg_achievements.get('课程目标4', 0) >= 0.7 else "一般")}。学生能够遵循软件工程规范，完成应用测试与优化。

### 2. 定性评价情况分析

从评价结果可以看出，学生在课程目标1和2方面表现较好，课程目标3和4相对较弱。主要原因可能是：

1. **技术更新快**：混合开发框架版本更新较快，学生对新特性掌握不及时
2. **工具复杂度高**：华为多端开发工具（DevEco Studio）操作复杂度较高，实验课时不足导致实操能力薄弱
3. **考核难度**：期末项目考核中跨设备适配场景设计占比过高，学生在多终端兼容性调试方面失分较多
4. **评分标准**：本课程在过程性考核中增加了AI工具应用能力的评分项，标准较上届更为严格

---

## 三、教学持续改进

### 1. 本轮教学持续改进措施的执行情况

针对上一轮该课程教学持续改进意见，在本轮教学中持续改进的措施执行情况如下：

#### （1）平时作业改进
- 在平时作业中加大关于运用移动应用开发技术体系分析实际应用问题的题目训练
- 实现期末考核内容与平时训练内容相一致

#### （2）知识拓展
- 在移动应用开发的每一章结束后，在作业中增加与该章知识点相关的英文期刊文献阅读培训
- 扩展学生的知识面并提高其英文文献的阅读与总结能力

#### （3）考核方式调整
- 调整平时、实验以及期末的课程成绩比例，增加实验成绩比例
- 降低平时和期末的课程比例，注重学生的过程性考核
- 实验环节注重每个实验的考核，提升学生对实际移动应用的开发与验证能力

### 2. 后续教学持续改进

针对本次课程目标达成评价情况分析，今后教学中拟采取以下改进措施：

#### （1）加强基础知识训练
- 拟在平时作业中加大关于运用移动应用开发技术体系分析实际应用问题的题目
- 加大跨平台开发方案的对比分析训练
- 实现期末考核内容与平时训练内容进一步保持一致

#### （2）拓展知识体系
- 在移动应用开发的每一章结束后，在作业中继续增加与该章知识点相关的知识图谱的创建
- 扩展学生的知识面并提高开发能力

#### （3）优化考核设计
- 进一步优化期末项目考核的场景设计
- 降低跨设备适配模块的分值占比（从40%调整为30%）
- 增加AI工具辅助开发的评分维度

#### （4）个性化帮扶
- 对过程性考核中课程目标值偏低的同学，给出具体的帮扶计划
- 额外增加跨设备适配实验练习
- 提供AI编程工具使用指南
- 组织技术专题工作坊

---

## 四、结论

通过本次课程达成度评价，我们可以看到：

1. **整体表现**：学生在移动应用开发课程的学习中取得了一定的成果，特别是在技术体系掌握和跨平台应用开发方面。

2. **优势领域**：课程目标1和2的达成度较高，说明学生在技术体系掌握和跨平台应用开发方面表现良好。

3. **待改进领域**：课程目标3和4相对较弱，特别是在多端应用开发和工程实践能力方面需要加强。

4. **改进方向**：通过持续的教学改进，我们相信学生的移动应用开发能力将得到进一步提升。

5. **未来展望**：为学生未来的职业发展奠定坚实的基础，培养具备现代移动应用开发能力的工程技术人才。

---

**报告生成完成**

""".format(
    avg_achievements.get('课程目标1', 0),
    avg_achievements.get('课程目标2', 0),
    avg_achievements.get('课程目标3', 0),
    avg_achievements.get('课程目标4', 0)
)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(report_content)
        
        return output_file
    
    def verify_previous_calculation(self, students, excel_path):
        """验证上届计算是否正确"""
        try:
            # 读取Excel中的课程目标达成度
            df = pd.read_excel(excel_path)
            
            # 找到课程目标达成度行
            achievement_row = -1
            for i, row in df.iterrows():
                if '课程目标达成度' in str(row.iloc[0]):
                    achievement_row = i
                    break
            
            if achievement_row == -1:
                return "未找到课程目标达成度数据"
            
            # 提取Excel中的达成度
            excel_achievements = {
                '课程目标1': float(df.loc[achievement_row, df.columns[3]]),
                '课程目标2': float(df.loc[achievement_row, df.columns[5]]),
                '课程目标3': float(df.loc[achievement_row, df.columns[7]]),
                '课程目标4': float(df.loc[achievement_row, df.columns[9]])
            }
            
            # 计算我们的达成度
            our_achievements = self.calculate_class_average(students)
            
            # 比较结果
            verification_results = []
            for obj in ['课程目标1', '课程目标2', '课程目标3', '课程目标4']:
                excel_val = excel_achievements.get(obj, 0)
                our_val = our_achievements.get(obj, 0)
                diff = abs(excel_val - our_val)
                status = "✓ 正确" if diff < 0.0001 else f"✗ 存在差异: Excel={excel_val:.4f}, 计算={our_val:.4f}"
                verification_results.append(f"{obj}: {status}")
            
            return "\n".join(verification_results)
        except Exception as e:
            return f"验证失败: {str(e)}"
    
    def run(self, excel_path, output_report):
        """运行完整流程"""
        try:
            print("=" * 60)
            print("课程达成度分析和评价系统")
            print("=" * 60)
            
            print("\n[1/6] 加载Excel数据...")
            df = self.load_excel_data(excel_path)
            print(f"✓ 成功加载Excel文件: {excel_path}")
            
            print("\n[2/6] 解析数据...")
            self.students = self.parse_excel_data(df)
            print(f"✓ 成功解析 {len(self.students)} 名学生数据")
            
            print("\n[3/6] 计算班级平均达成度...")
            self.avg_achievements = self.calculate_class_average(self.students)
            for obj, val in self.avg_achievements.items():
                print(f"  {obj}: {val:.4f}")
            
            print("\n[4/6] 计算加权达成度...")
            self.weighted_achievement = self.calculate_weighted_achievement(self.avg_achievements)
            print(f"✓ 加权总达成度: {self.weighted_achievement:.4f}")
            
            print("\n[5/6] 生成可视化图表...")
            viz_dir = self.generate_visualizations(self.avg_achievements)
            print(f"✓ 可视化图表已保存到: {viz_dir}")
            
            print("\n[6/6] 生成报告...")
            report_file = self.generate_markdown_report(
                self.students, 
                self.avg_achievements, 
                self.weighted_achievement, 
                output_report
            )
            print(f"✓ 报告已生成: {report_file}")
            
            print("\n" + "=" * 60)
            print("验证上届计算结果:")
            print("=" * 60)
            verification = self.verify_previous_calculation(self.students, excel_path)
            print(verification)
            
            print("\n" + "=" * 60)
            print("处理完成！")
            print("=" * 60)
            
            return report_file
            
        except Exception as e:
            print(f"\n✗ 错误: {str(e)}")
            raise


class CourseAchievementGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("课程达成度分析和评价系统")
        self.root.geometry("800x600")
        
        self.system = CourseAchievementSystem()
        self.current_file = None
        
        self.create_widgets()
    
    def create_widgets(self):
        # 标题
        title_label = tk.Label(
            self.root, 
            text="课程达成度分析和评价系统", 
            font=("Microsoft YaHei", 16, "bold")
        )
        title_label.pack(pady=20)
        
        # 文件选择区域
        file_frame = tk.LabelFrame(self.root, text="数据文件", font=("Microsoft YaHei", 12))
        file_frame.pack(pady=10, padx=20, fill="x")
        
        self.file_label = tk.Label(file_frame, text="未选择文件", font=("Microsoft YaHei", 10))
        self.file_label.pack(pady=10, padx=10)
        
        button_frame = tk.Frame(file_frame)
        button_frame.pack(pady=5)
        
        select_button = tk.Button(
            button_frame, 
            text="选择Excel文件", 
            command=self.select_file,
            font=("Microsoft YaHei", 10),
            bg="#4ECDC4",
            fg="white",
            width=15
        )
        select_button.pack(side="left", padx=5)
        
        # 操作区域
        action_frame = tk.LabelFrame(self.root, text="操作", font=("Microsoft YaHei", 12))
        action_frame.pack(pady=10, padx=20, fill="x")
        
        run_button = tk.Button(
            action_frame, 
            text="开始分析", 
            command=self.run_analysis,
            font=("Microsoft YaHei", 10),
            bg="#FF6B6B",
            fg="white",
            width=15
        )
        run_button.pack(pady=10)
        
        # 结果显示区域
        result_frame = tk.LabelFrame(self.root, text="分析结果", font=("Microsoft YaHei", 12))
        result_frame.pack(pady=10, padx=20, fill="both", expand=True)
        
        self.result_text = tk.Text(result_frame, font=("Microsoft YaHei", 9))
        scrollbar = tk.Scrollbar(result_frame, command=self.result_text.yview)
        self.result_text.configure(yscrollcommand=scrollbar.set)
        
        self.result_text.pack(side="left", fill="both", expand=True, padx=5, pady=5)
        scrollbar.pack(side="right", fill="y")
        
        # 状态栏
        self.status_label = tk.Label(
            self.root, 
            text="就绪", 
            relief=tk.SUNKEN, 
            anchor=tk.W,
            font=("Microsoft YaHei", 9)
        )
        self.status_label.pack(side=tk.BOTTOM, fill="x")
    
    def select_file(self):
        file_path = filedialog.askopenfilename(
            title="选择Excel文件",
            filetypes=[("Excel文件", "*.xlsx *.xls")]
        )
        if file_path:
            self.current_file = file_path
            self.file_label.config(text=os.path.basename(file_path))
            self.status_label.config(text=f"已选择文件: {file_path}")
    
    def run_analysis(self):
        if not self.current_file:
            messagebox.showwarning("警告", "请先选择Excel文件！")
            return
        
        try:
            self.result_text.delete(1.0, tk.END)
            self.status_label.config(text="正在分析...")
            self.root.update()
            
            # 生成输出文件名
            output_dir = os.path.dirname(self.current_file)
            output_report = os.path.join(output_dir, "软件23+6+《移动应用开发》课程达成度报告.md")
            
            # 运行分析
            report_file = self.system.run(self.current_file, output_report)
            
            # 显示结果
            self.result_text.insert(tk.END, f"分析完成！\n\n")
            self.result_text.insert(tk.END, f"学生人数: {len(self.system.students)}\n")
            self.result_text.insert(tk.END, f"加权总达成度: {self.system.weighted_achievement:.4f}\n\n")
            self.result_text.insert(tk.END, "课程目标达成度:\n")
            for obj, val in self.system.avg_achievements.items():
                if obj != '总评':
                    self.result_text.insert(tk.END, f"  {obj}: {val:.4f}\n")
            
            self.status_label.config(text=f"分析完成！报告已保存: {report_file}")
            messagebox.showinfo("完成", f"分析完成！\n报告已保存: {report_file}")
            
        except Exception as e:
            self.result_text.insert(tk.END, f"错误: {str(e)}\n")
            self.status_label.config(text=f"分析失败: {str(e)}")
            messagebox.showerror("错误", f"分析失败: {str(e)}")


def main():
    root = tk.Tk()
    app = CourseAchievementGUI(root)
    root.mainloop()

if __name__ == "__main__":
    # 命令行模式
    if len(sys.argv) > 1:
        calculator = CourseAchievementSystem()
        excel_path = sys.argv[1]
        output_report = sys.argv[2] if len(sys.argv) > 2 else '软件23+6+《移动应用开发》课程达成度报告.md'
        calculator.run(excel_path, output_report)
    else:
        # GUI模式
        main()