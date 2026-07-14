import pandas as pd
import numpy as np

# 读取Excel文件
df = pd.read_excel('计科22《移动应用开发》课程达成评价表格48.xlsx')

# 查看前几行数据
print("前10行数据:")
print(df.head(10))

# 查看列名
print("\n列名:")
print(df.columns.tolist())

# 查看数据类型
print("\n数据类型:")
print(df.dtypes)

# 查看基本统计信息
print("\n基本统计信息:")
print(df.describe())

# 查看是否有缺失值
print("\n缺失值情况:")
print(df.isnull().sum())

# 分析达成度计算方法
# 查找包含"达成度"的列
achievement_cols = [col for col in df.columns if '达成度' in col]
print("\n达成度相关列:")
print(achievement_cols)

# 分析成绩列
score_cols = [col for col in df.columns if '成绩' in col or '得分' in col]
print("\n成绩相关列:")
print(score_cols)