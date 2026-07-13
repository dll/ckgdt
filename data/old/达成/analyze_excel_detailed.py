import pandas as pd
import numpy as np

# 读取Excel文件
df = pd.read_excel('计科22《移动应用开发》课程达成评价表格48.xlsx')

# 查看完整的表格内容
print("完整表格内容:")
for i, row in df.iterrows():
    print(f"行 {i}: {row.tolist()}")

# 尝试解析表格结构
print("\n尝试解析表格结构:")
# 查找表头行
header_row = -1
for i, row in df.iterrows():
    if '课程目标' in str(row.iloc[0]):
        header_row = i
        break

if header_row != -1:
    print(f"找到表头行: {header_row}")
    # 提取表头
    headers = []
    for col in df.columns:
        header_val = str(df.loc[header_row, col])
        if header_val != 'nan':
            headers.append(header_val)
        else:
            headers.append('')
    print(f"表头: {headers}")
    
    # 提取数据行
    data_rows = []
    for i in range(header_row + 2, len(df)):
        row_data = []
        for col in df.columns:
            val = df.loc[i, col]
            if str(val) != 'nan':
                row_data.append(val)
            else:
                row_data.append('')
        if any(row_data):  # 跳过空行
            data_rows.append(row_data)
    
    print(f"数据行数: {len(data_rows)}")
    print("前5行数据:")
    for i, row in enumerate(data_rows[:5]):
        print(f"行 {i}: {row}")
else:
    print("未找到表头行")

# 尝试提取课程目标和达成度数据
print("\n尝试提取课程目标和达成度数据:")
# 查找包含"达成度"的单元格
for i, row in df.iterrows():
    for j, val in enumerate(row):
        if '达成度' in str(val):
            print(f"找到达成度数据: 行 {i}, 列 {j}, 值: {val}")

# 查找包含"课程目标"的单元格
for i, row in df.iterrows():
    for j, val in enumerate(row):
        if '课程目标' in str(val):
            print(f"找到课程目标数据: 行 {i}, 列 {j}, 值: {val}")