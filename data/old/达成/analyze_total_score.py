import pandas as pd

# 读取Excel文件
df = pd.read_excel('计科22《移动应用开发》课程达成评价表格48.xlsx')

# 找到班平均值行
class_avg_row = -1
for i, row in df.iterrows():
    if '班平均值' in str(row.iloc[0]):
        class_avg_row = i
        break

if class_avg_row != -1:
    print("班平均值行数据:")
    for j, val in enumerate(df.loc[class_avg_row]):
        print(f"列 {j}: {val}")

# 计算学生总评的平均值
header_row = -1
for i, row in df.iterrows():
    if '课程目标' in str(row.iloc[0]):
        header_row = i
        break

if header_row != -1:
    # 提取学生数据
    total_scores = []
    for i in range(header_row + 3, len(df)):
        val = df.loc[i, df.columns[10]]
        if str(val) != 'nan':
            try:
                total_scores.append(float(val))
            except:
                pass
    
    print(f"\n学生总评得分数量: {len(total_scores)}")
    print(f"学生总评得分平均值: {sum(total_scores) / len(total_scores) if total_scores else 0}")
    print(f"学生总评得分平均值(转换为0-1范围): {sum(total_scores) / len(total_scores) / 100 if total_scores else 0}")

# 查看Excel中的总评计算公式
print("\n尝试分析总评计算逻辑:")
print("从Excel数据看，总评得分似乎是直接计算的，而不是通过达成度计算的")
print("让我们检查前几行数据的总评计算:")

for i in range(header_row + 3, header_row + 8):
    if i < len(df):
        row = df.loc[i]
        print(f"\n学生 {i - header_row - 3}:")
        print(f"学号: {row.iloc[0]}")
        print(f"姓名: {row.iloc[1]}")
        print(f"目标1得分: {row.iloc[2]}")
        print(f"目标2得分: {row.iloc[4]}")
        print(f"目标3得分: {row.iloc[6]}")
        print(f"目标4得分: {row.iloc[8]}")
        print(f"总评得分: {row.iloc[10]}")
        
        # 尝试计算总评
        try:
            score1 = float(row.iloc[2])
            score2 = float(row.iloc[4])
            score3 = float(row.iloc[6])
            score4 = float(row.iloc[8])
            total = float(row.iloc[10])
            
            # 尝试不同的权重组合
            weights = [0.15, 0.25, 0.30, 0.30]
            calculated = score1 * weights[0] + score2 * weights[1] + score3 * weights[2] + score4 * weights[3]
            print(f"按课程目标权重计算: {calculated:.2f}")
            print(f"与Excel总评的差异: {abs(total - calculated):.2f}")
            
            # 尝试直接相加
            sum_scores = score1 + score2 + score3 + score4
            print(f"直接相加: {sum_scores:.2f}")
            
        except Exception as e:
            print(f"计算错误: {e}")