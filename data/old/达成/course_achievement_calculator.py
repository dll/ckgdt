import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from docx import Document
import markdown
import os

class CourseAchievementCalculator:
    def __init__(self):
        # 课程目标权重
        self.objective_weights = {
            '目标1': 0.15,
            '目标2': 0.25,
            '目标3': 0.30,
            '目标4': 0.30
        }
        # 评估类型权重
        self.assessment_weights = {
            '平时': 0.20,
            '实验': 0.30,
            '期末': 0.50
        }
        # 课程目标对应关系
        self.objective_mapping = {
            '目标1': '课程目标1',
            '目标2': '课程目标2',
            '目标3': '课程目标3',
            '目标4': '课程目标4'
        }
    
    def load_excel_data(self, excel_path):
        """加载Excel数据"""
        df = pd.read_excel(excel_path)
        return df
    
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
                student = {
                    '学号': row[0],
                    '姓名': row[1],
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
        
        return students
    
    def calculate_class_average(self, students):
        """计算班级平均达成度"""
        if not students:
            return {}
        
        avg_achievements = {
            '目标1': np.mean([s['目标1达成度'] for s in students]),
            '目标2': np.mean([s['目标2达成度'] for s in students]),
            '目标3': np.mean([s['目标3达成度'] for s in students]),
            '目标4': np.mean([s['目标4达成度'] for s in students]),
            '总评': np.mean([s['总评得分'] for s in students]) / 100  # 保持与Excel一致，总评满分为100
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
        sns.barplot(x=objectives, y=achievements)
        plt.title('课程目标达成度')
        plt.ylabel('达成度')
        plt.ylim(0, 1)
        plt.savefig(os.path.join(output_dir, 'course_objective_achievement.png'))
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
        
        ax.plot(angles, values, 'o-', linewidth=2, label='达成度')
        ax.fill(angles, values, alpha=0.25)
        ax.set_thetagrids([a * 180/pi for a in angles[:-1]], categories)
        ax.set_ylim(0, 1)
        plt.title('课程目标达成度雷达图')
        plt.legend(loc='upper right', bbox_to_anchor=(0.1, 0.1))
        plt.savefig(os.path.join(output_dir, 'course_objective_radar.png'))
        plt.close()
        
        return output_dir
    
    def generate_markdown_report(self, students, avg_achievements, weighted_achievement, output_file):
        """生成Markdown报告"""
        report_content = f"""# 软件23+6+《移动应用开发》课程达成度报告

## 一、课程目标达成情况

### 1. 班级平均达成度

| 课程目标 | 达成度 |
|---------|-------|
| 课程目标1 | {avg_achievements.get('目标1', 0):.4f} |
| 课程目标2 | {avg_achievements.get('目标2', 0):.4f} |
| 课程目标3 | {avg_achievements.get('目标3', 0):.4f} |
| 课程目标4 | {avg_achievements.get('目标4', 0):.4f} |
| **加权总达成度** | {weighted_achievement:.4f} |

### 2. 学生个体达成情况

共有 {len(students)} 名学生参与评价。

## 二、达成度分析

### 1. 定量评价情况分析

课程目标1主要考核学生掌握移动应用开发技术体系及主流平台特性，理解技术选型逻辑，熟悉跨平台开发框架和AI编程工具的基本使用。

课程目标2主要考核学生运用跨平台开发框架及小程序技术，结合AI编程工具与后端API交互，设计实现跨平台应用，具备需求建模与创新应用能力。

课程目标3主要考核学生调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力。

课程目标4主要考核学生遵循软件工程规范，使用现代开发工具完成应用测试与优化，具备工程实践能力。

### 2. 定性评价情况分析

从评价结果可以看出，学生在课程目标1和2方面表现较好，课程目标3和4相对较弱。主要原因可能是：

1. 混合开发框架版本更新较快，学生对新特性掌握不及时
2. 华为多端开发工具（DevEco Studio）操作复杂度较高，实验课时不足导致实操能力薄弱
3. 期末项目考核中跨设备适配场景设计占比过高，学生在多终端兼容性调试方面失分较多
4. 本课程在过程性考核中增加了AI工具应用能力的评分项，标准较上届更为严格

## 三、教学持续改进

### 1. 本轮教学持续改进措施的执行情况

针对上一轮该课程教学持续改进意见，在本轮教学中持续改进的措施执行情况如下：

1. 在平时作业中加大关于运用移动应用开发技术体系分析实际应用问题的题目训练，实现期末考核内容与平时训练内容相一致
2. 在移动应用开发的每一章结束后，在作业中增加与该章知识点相关的英文期刊文献阅读培训，扩展学生的知识面并提高其英文文献的阅读与总结能力
3. 调整平时、实验以及期末的课程成绩比例，增加实验成绩比例，降低平时和期末的课程比例，注重学生的过程性考核，实验环节注重每个实验的考核，提升学生对实际移动应用的开发与验证能力

### 2. 后续教学持续改进

针对本次课程目标达成评价情况分析，今后教学中拟采取以下改进措施：

1. 拟在平时作业中加大关于运用移动应用开发技术体系分析实际应用问题的题目，以及加大跨平台开发方案的对比分析训练，实现期末考核内容与平时训练内容进一步保持一致
2. 在移动应用开发的每一章结束后，在作业中继续增加与该章知识点相关的知识图谱的创建，扩展学生的知识面并提高开发能力
3. 进一步优化期末项目考核的场景设计，降低跨设备适配模块的分值占比，增加AI工具辅助开发的评分维度
4. 对过程性考核中课程目标值偏低的同学，给出具体的帮扶计划（如额外增加跨设备适配实验练习、提供AI编程工具使用指南、组织技术专题工作坊等）

## 四、结论

通过本次课程达成度评价，我们可以看到学生在移动应用开发课程的学习中取得了一定的成果，特别是在技术体系掌握和跨平台应用开发方面。同时，我们也发现了一些需要改进的地方，特别是在多端应用开发和工程实践能力方面。

通过持续的教学改进，我们相信学生的移动应用开发能力将得到进一步提升，为他们未来的职业发展奠定坚实的基础。
"""
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(report_content)
        
        return output_file
    
    def verify_previous_calculation(self, students, excel_path):
        """验证上届计算是否正确"""
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
            '目标1': float(df.loc[achievement_row, df.columns[3]]),
            '目标2': float(df.loc[achievement_row, df.columns[5]]),
            '目标3': float(df.loc[achievement_row, df.columns[7]]),
            '目标4': float(df.loc[achievement_row, df.columns[9]])
        }
        
        # 计算我们的达成度
        our_achievements = self.calculate_class_average(students)
        
        # 比较结果
        verification_results = []
        for obj in ['目标1', '目标2', '目标3', '目标4']:
            excel_val = excel_achievements.get(obj, 0)
            our_val = our_achievements.get(obj, 0)
            diff = abs(excel_val - our_val)
            status = "正确" if diff < 0.0001 else f"存在差异: Excel={excel_val:.4f}, 计算={our_val:.4f}"
            verification_results.append(f"{obj}: {status}")
        
        return "\n".join(verification_results)

    def run(self, excel_path, output_report):
        """运行完整流程"""
        print("加载Excel数据...")
        df = self.load_excel_data(excel_path)
        
        print("解析数据...")
        students = self.parse_excel_data(df)
        
        print("计算班级平均达成度...")
        avg_achievements = self.calculate_class_average(students)
        
        print("计算加权达成度...")
        weighted_achievement = self.calculate_weighted_achievement(avg_achievements)
        
        print("生成可视化图表...")
        self.generate_visualizations(avg_achievements)
        
        print("生成报告...")
        report_file = self.generate_markdown_report(students, avg_achievements, weighted_achievement, output_report)
        
        print("验证上届计算...")
        verification = self.verify_previous_calculation(students, excel_path)
        
        print("\n验证结果:")
        print(verification)
        
        print(f"\n报告已生成: {report_file}")
        return report_file

if __name__ == "__main__":
    calculator = CourseAchievementCalculator()
    excel_path = '计科22《移动应用开发》课程达成评价表格48.xlsx'
    output_report = '软件23+6+《移动应用开发》课程达成度报告.md'
    calculator.run(excel_path, output_report)