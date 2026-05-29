# 嵌入式C/C++开发技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：C / C++
- **开发框架**：嵌入式系统框架
- **硬件平台**：STM32、ESP32、Arduino、Raspberry Pi
- **开发工具**：Keil MDK、STM32CubeIDE、VS Code + PlatformIO
- **版本要求**：C99、C++11+

### 1.2 依赖管理
- **包管理**：PlatformIO、Arduino Library Manager
- **依赖仓库**：PlatformIO Registry、Arduino Library
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：Unity、Google Test
- **硬件测试**：硬件在环测试（HIL）
- **集成测试**：嵌入式测试框架

## 二、环境搭建

### 2.1 STM32开发环境

```ini
; platformio.ini
[env:stm32f4]
platform = ststm32
board = nucleo_f411re
framework = stm32cube

build_flags = 
    -DUSE_HAL_DRIVER
    -DSTM32F411xE

lib_deps = 
    bxparks/AceCommon@^1.7.0
    bxparks/AceSegment@^1.2.0

monitor_speed = 115200
```

### 2.2 ESP32开发环境

```ini
; platformio.ini
[env:esp32]
platform = espressif32
board = esp32dev
framework = arduino

build_flags = 
    -DCORE_DEBUG_LEVEL=3
    -DBOARD_HAS_PSRAM

lib_deps = 
    bblanchon/ArduinoJson@^6.21.0
    bblanchon/PubSubClient@^2.8

monitor_speed = 115200
upload_speed = 921600
```

### 2.3 Arduino开发环境

```ini
; platformio.ini
[env:uno]
platform = atmelavr
board = uno
framework = arduino

lib_deps = 
    adafruit/Adafruit Unified Sensor@^1.1.9
    adafruit/DHT sensor library@^1.4.4

monitor_speed = 9600
```

## 三、基础语法与特性

### 3.1 C语言基础

#### 3.1.1 变量声明

```c
#include <stdint.h>

// 基本数据类型
int age = 25;
float temperature = 36.5;
char grade = 'A';

// 固定宽度整数类型
uint8_t byte_value = 255;
int16_t short_value = -32768;
uint32_t long_value = 4294967295;

// 常量
const int MAX_COUNT = 100;
#define PI 3.14159f

// 数组
int numbers[5] = {1, 2, 3, 4, 5};
char message[] = "Hello World";

// 结构体
typedef struct {
    uint8_t id;
    char name[32];
    float value;
} SensorData;

// 枚举
typedef enum {
    SENSOR_OK,
    SENSOR_ERROR,
    SENSOR_TIMEOUT
} SensorStatus;
```

#### 3.1.2 函数定义

```c
// 基本函数
int add(int a, int b) {
    return a + b;
}

// 函数声明
float calculate_average(int* values, int count);

// 指针函数
void swap(int* a, int* b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

// 函数指针
typedef int (*OperationFunc)(int, int);

int perform_operation(int a, int b, OperationFunc op) {
    return op(a, b);
}

// 使用函数指针
int result = perform_operation(10, 20, add);

// 可变参数函数
#include <stdarg.h>

int sum_all(int count, ...) {
    va_list args;
    va_start(args, count);
    
    int sum = 0;
    for (int i = 0; i < count; i++) {
        sum += va_arg(args, int);
    }
    
    va_end(args);
    return sum;
}
```

#### 3.1.3 指针与内存管理

```c
#include <stdlib.h>
#include <string.h>

// 指针基础
int value = 10;
int* ptr = &value;
*ptr = 20;  // 修改value的值

// 动态内存分配
int* array = (int*)malloc(10 * sizeof(int));
if (array != NULL) {
    for (int i = 0; i < 10; i++) {
        array[i] = i;
    }
    free(array);  // 释放内存
}

// 内存操作
void memory_operations() {
    char src[] = "Hello";
    char dest[10];
    
    memcpy(dest, src, strlen(src) + 1);  // 复制内存
    memset(dest, 0, sizeof(dest));      // 填充内存
    memcmp(dest, src, strlen(src));      // 比较内存
}

// 指针数组
int* ptr_array[5];
for (int i = 0; i < 5; i++) {
    ptr_array[i] = (int*)malloc(sizeof(int));
    *ptr_array[i] = i;
}

// 释放指针数组
for (int i = 0; i < 5; i++) {
    free(ptr_array[i]);
}
```

### 3.2 C++特性

#### 3.2.1 类与对象

```cpp
#include <iostream>
#include <string>

class Sensor {
private:
    int _id;
    std::string _name;
    float _value;

public:
    // 构造函数
    Sensor(int id, const std::string& name) 
        : _id(id), _name(name), _value(0.0f) {}
    
    // 析构函数
    ~Sensor() {
        std::cout << "Sensor destroyed" << std::endl;
    }
    
    // Getter方法
    int getId() const { return _id; }
    const std::string& getName() const { return _name; }
    float getValue() const { return _value; }
    
    // Setter方法
    void setValue(float value) { _value = value; }
    
    // 方法
    void read() {
        _value = read_sensor_value();
    }
    
    // 静态方法
    static Sensor createDefault() {
        return Sensor(0, "Default");
    }

private:
    float read_sensor_value() {
        return 25.0f;  // 模拟读取传感器值
    }
};

// 使用类
Sensor sensor(1, "Temperature");
sensor.read();
std::cout << "Value: " << sensor.getValue() << std::endl;
```

#### 3.2.2 模板

```cpp
// 函数模板
template <typename T>
T max_value(T a, T b) {
    return (a > b) ? a : b;
}

// 使用函数模板
int max_int = max_value(10, 20);
float max_float = max_value(3.14f, 2.71f);

// 类模板
template <typename T>
class Buffer {
private:
    T* _data;
    size_t _size;

public:
    Buffer(size_t size) : _size(size) {
        _data = new T[size];
    }
    
    ~Buffer() {
        delete[] _data;
    }
    
    T& operator[](size_t index) {
        return _data[index];
    }
    
    const T& operator[](size_t index) const {
        return _data[index];
    }
};

// 使用类模板
Buffer<int> int_buffer(10);
Buffer<float> float_buffer(10);
```

#### 3.2.3 异常处理

```cpp
#include <stdexcept>

class SensorException : public std::runtime_error {
public:
    SensorException(const std::string& message) 
        : std::runtime_error(message) {}
};

class AdvancedSensor {
public:
    float readValue() {
        float value = read_hardware();
        
        if (value < 0.0f || value > 100.0f) {
            throw SensorException("Invalid sensor value");
        }
        
        return value;
    }

private:
    float read_hardware() {
        return -1.0f;  // 模拟错误值
    }
};

// 使用异常处理
try {
    AdvancedSensor sensor;
    float value = sensor.readValue();
    std::cout << "Value: " << value << std::endl;
} catch (const SensorException& e) {
    std::cerr << "Error: " << e.what() << std::endl;
} catch (const std::exception& e) {
    std::cerr << "Unknown error: " << e.what() << std::endl;
}
```

## 四、硬件驱动开发

### 4.1 GPIO控制

```c
#include "stm32f4xx_hal.h"

// GPIO初始化
void GPIO_Init(void) {
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    
    // 使能GPIO时钟
    __HAL_RCC_GPIOA_CLK_ENABLE();
    
    // 配置GPIO引脚
    GPIO_InitStruct.Pin = GPIO_PIN_5;
    GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);
}

// GPIO输出控制
void GPIO_WriteHigh(void) {
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET);
}

void GPIO_WriteLow(void) {
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_RESET);
}

void GPIO_Toggle(void) {
    HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
}

// GPIO输入读取
GPIO_PinState GPIO_Read(void) {
    return HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_0);
}
```

### 4.2 UART通信

```c
#include "stm32f4xx_hal.h"

UART_HandleTypeDef huart1;

// UART初始化
void UART_Init(void) {
    huart1.Instance = USART1;
    huart1.Init.BaudRate = 115200;
    huart1.Init.WordLength = UART_WORDLENGTH_8B;
    huart1.Init.StopBits = UART_STOPBITS_1;
    huart1.Init.Parity = UART_PARITY_NONE;
    huart1.Init.Mode = UART_MODE_TX_RX;
    huart1.Init.HwFlowCtl = UART_HWCONTROL_NONE;
    huart1.Init.OverSampling = UART_OVERSAMPLING_16;
    
    if (HAL_UART_Init(&huart1) != HAL_OK) {
        Error_Handler();
    }
}

// UART发送数据
void UART_SendString(const char* str) {
    HAL_UART_Transmit(&huart1, (uint8_t*)str, strlen(str), HAL_MAX_DELAY);
}

void UART_SendByte(uint8_t byte) {
    HAL_UART_Transmit(&huart1, &byte, 1, HAL_MAX_DELAY);
}

// UART接收数据
void UART_ReceiveByte(uint8_t* byte) {
    HAL_UART_Receive(&huart1, byte, 1, HAL_MAX_DELAY);
}

// UART中断接收
uint8_t rx_buffer[100];
volatile uint16_t rx_index = 0;

void UART_ReceiveIT(void) {
    HAL_UART_Receive_IT(&huart1, &rx_buffer[rx_index], 1);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart) {
    if (huart->Instance == USART1) {
        rx_index++;
        if (rx_index >= sizeof(rx_buffer)) {
            rx_index = 0;
        }
        HAL_UART_Receive_IT(&huart1, &rx_buffer[rx_index], 1);
    }
}
```

### 4.3 I2C通信

```c
#include "stm32f4xx_hal.h"

I2C_HandleTypeDef hi2c1;

// I2C初始化
void I2C_Init(void) {
    hi2c1.Instance = I2C1;
    hi2c1.Init.ClockSpeed = 100000;
    hi2c1.Init.DutyCycle = I2C_DUTYCYCLE_2;
    hi2c1.Init.OwnAddress1 = 0;
    hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
    hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
    hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
    hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
    
    if (HAL_I2C_Init(&hi2c1) != HAL_OK) {
        Error_Handler();
    }
}

// I2C写数据
HAL_StatusTypeDef I2C_Write(uint8_t device_addr, uint8_t reg_addr, uint8_t* data, uint16_t length) {
    return HAL_I2C_Mem_Write(&hi2c1, device_addr << 1, reg_addr, I2C_MEMADD_SIZE_8BIT, data, length, HAL_MAX_DELAY);
}

// I2C读数据
HAL_StatusTypeDef I2C_Read(uint8_t device_addr, uint8_t reg_addr, uint8_t* data, uint16_t length) {
    return HAL_I2C_Mem_Read(&hi2c1, device_addr << 1, reg_addr, I2C_MEMADD_SIZE_8BIT, data, length, HAL_MAX_DELAY);
}

// 读取单个字节
uint8_t I2C_ReadByte(uint8_t device_addr, uint8_t reg_addr) {
    uint8_t data;
    I2C_Read(device_addr, reg_addr, &data, 1);
    return data;
}

// 写入单个字节
void I2C_WriteByte(uint8_t device_addr, uint8_t reg_addr, uint8_t data) {
    I2C_Write(device_addr, reg_addr, &data, 1);
}
```

### 4.4 SPI通信

```c
#include "stm32f4xx_hal.h"

SPI_HandleTypeDef hspi1;

// SPI初始化
void SPI_Init(void) {
    hspi1.Instance = SPI1;
    hspi1.Init.Mode = SPI_MODE_MASTER;
    hspi1.Init.Direction = SPI_DIRECTION_2LINES;
    hspi1.Init.DataSize = SPI_DATASIZE_8BIT;
    hspi1.Init.CLKPolarity = SPI_POLARITY_LOW;
    hspi1.Init.CLKPhase = SPI_PHASE_1EDGE;
    hspi1.Init.NSS = SPI_NSS_SOFT;
    hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_16;
    hspi1.Init.FirstBit = SPI_FIRSTBIT_MSB;
    hspi1.Init.TIMode = SPI_TIMODE_DISABLE;
    hspi1.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
    hspi1.Init.CRCPolynomial = 10;
    
    if (HAL_SPI_Init(&hspi1) != HAL_OK) {
        Error_Handler();
    }
}

// SPI发送接收数据
HAL_StatusTypeDef SPI_TransmitReceive(uint8_t* tx_data, uint8_t* rx_data, uint16_t length) {
    return HAL_SPI_TransmitReceive(&hspi1, tx_data, rx_data, length, HAL_MAX_DELAY);
}

// SPI发送数据
HAL_StatusTypeDef SPI_Transmit(uint8_t* data, uint16_t length) {
    return HAL_SPI_Transmit(&hspi1, data, length, HAL_MAX_DELAY);
}

// SPI接收数据
HAL_StatusTypeDef SPI_Receive(uint8_t* data, uint16_t length) {
    return HAL_SPI_Receive(&hspi1, data, length, HAL_MAX_DELAY);
}

// 读取单个字节
uint8_t SPI_ReadByte(void) {
    uint8_t tx_data = 0xFF;
    uint8_t rx_data = 0;
    SPI_TransmitReceive(&tx_data, &rx_data, 1);
    return rx_data;
}

// 写入单个字节
void SPI_WriteByte(uint8_t data) {
    uint8_t rx_data = 0;
    SPI_TransmitReceive(&data, &rx_data, 1);
}
```

## 五、传感器驱动开发

### 5.1 DHT温湿度传感器

```c
#include "stm32f4xx_hal.h"

#define DHT_PIN GPIO_PIN_0
#define DHT_PORT GPIOA

void DHT_Start(void) {
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    
    // 配置为输出
    GPIO_InitStruct.Pin = DHT_PIN;
    GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(DHT_PORT, &GPIO_InitStruct);
    
    // 拉低18ms
    HAL_GPIO_WritePin(DHT_PORT, DHT_PIN, GPIO_PIN_RESET);
    HAL_Delay(18);
    
    // 拉高
    HAL_GPIO_WritePin(DHT_PORT, DHT_PIN, GPIO_PIN_SET);
    HAL_Delay(20);
    
    // 配置为输入
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_PULLUP;
    HAL_GPIO_Init(DHT_PORT, &GPIO_InitStruct);
}

uint8_t DHT_CheckResponse(void) {
    uint8_t response = 0;
    
    // 等待DHT拉低
    uint32_t timeout = 100;
    while (HAL_GPIO_ReadPin(DHT_PORT, DHT_PIN) && timeout--) {
        HAL_Delay(1);
    }
    
    if (timeout == 0) return 0;
    HAL_Delay(80);
    
    // 等待DHT拉高
    timeout = 100;
    while (!HAL_GPIO_ReadPin(DHT_PORT, DHT_PIN) && timeout--) {
        HAL_Delay(1);
    }
    
    if (timeout == 0) return 0;
    HAL_Delay(80);
    
    return 1;
}

uint8_t DHT_ReadByte(void) {
    uint8_t byte = 0;
    
    for (int i = 0; i < 8; i++) {
        // 等待拉低
        while (HAL_GPIO_ReadPin(DHT_PORT, DHT_PIN));
        HAL_Delay(40);
        
        // 等待拉高
        while (!HAL_GPIO_ReadPin(DHT_PORT, DHT_PIN));
        
        // 延迟判断0或1
        HAL_Delay(40);
        byte <<= 1;
        if (HAL_GPIO_ReadPin(DHT_PORT, DHT_PIN)) {
            byte |= 1;
        }
    }
    
    return byte;
}

uint8_t DHT_ReadData(float* temperature, float* humidity) {
    uint8_t data[5] = {0};
    
    DHT_Start();
    
    if (!DHT_CheckResponse()) {
        return 0;
    }
    
    for (int i = 0; i < 5; i++) {
        data[i] = DHT_ReadByte();
    }
    
    // 校验和检查
    if (data[4] != (data[0] + data[1] + data[2] + data[3])) {
        return 0;
    }
    
    *humidity = (float)data[0] + (float)data[1] / 10.0f;
    *temperature = (float)data[2] + (float)data[3] / 10.0f;
    
    return 1;
}
```

### 5.2 MPU6050陀螺仪加速度计

```c
#include "stm32f4xx_hal.h"

#define MPU6050_ADDR 0x68 << 1

// MPU6050寄存器地址
#define MPU6050_PWR_MGMT_1   0x6B
#define MPU6050_GYRO_CONFIG  0x1B
#define MPU6050_ACCEL_CONFIG 0x1C
#define MPU6050_ACCEL_XOUT_H 0x3B

void MPU6050_Init(void) {
    // 唤醒MPU6050
    I2C_WriteByte(MPU6050_ADDR, MPU6050_PWR_MGMT_1, 0x00);
    
    // 配置陀螺仪范围：±250度/秒
    I2C_WriteByte(MPU6050_ADDR, MPU6050_GYRO_CONFIG, 0x00);
    
    // 配置加速度计范围：±2g
    I2C_WriteByte(MPU6050_ADDR, MPU6050_ACCEL_CONFIG, 0x00);
}

void MPU6050_ReadRaw(int16_t* accel_x, int16_t* accel_y, int16_t* accel_z,
                     int16_t* gyro_x, int16_t* gyro_y, int16_t* gyro_z) {
    uint8_t buffer[14];
    
    // 读取14字节数据
    I2C_Read(MPU6050_ADDR, MPU6050_ACCEL_XOUT_H, buffer, 14);
    
    // 解析加速度计数据
    *accel_x = (int16_t)((buffer[0] << 8) | buffer[1]);
    *accel_y = (int16_t)((buffer[2] << 8) | buffer[3]);
    *accel_z = (int16_t)((buffer[4] << 8) | buffer[5]);
    
    // 跳过温度数据
    // *temp = (int16_t)((buffer[6] << 8) | buffer[7]);
    
    // 解析陀螺仪数据
    *gyro_x = (int16_t)((buffer[8] << 8) | buffer[9]);
    *gyro_y = (int16_t)((buffer[10] << 8) | buffer[11]);
    *gyro_z = (int16_t)((buffer[12] << 8) | buffer[13]);
}

void MPU6050_ReadReal(float* accel_x, float* accel_y, float* accel_z,
                      float* gyro_x, float* gyro_y, float* gyro_z) {
    int16_t raw_ax, raw_ay, raw_az;
    int16_t raw_gx, raw_gy, raw_gz;
    
    MPU6050_ReadRaw(&raw_ax, &raw_ay, &raw_az, &raw_gx, &raw_gy, &raw_gz);
    
    // 转换为实际值
    *accel_x = raw_ax / 16384.0f;  // ±2g范围
    *accel_y = raw_ay / 16384.0f;
    *accel_z = raw_az / 16384.0f;
    
    *gyro_x = raw_gx / 131.0f;     // ±250度/秒范围
    *gyro_y = raw_gy / 131.0f;
    *gyro_z = raw_gz / 131.0f;
}
```

## 六、项目实战案例

### 6.1 项目一：农业大棚监控系统

#### 6.1.1 项目概述
开发一个农业大棚监控系统，包含温湿度监测、光照检测、土壤湿度监测等功能。

#### 6.1.2 核心功能实现

**主程序**

```c
#include "stm32f4xx_hal.h"
#include <stdio.h>

// 传感器数据结构
typedef struct {
    float temperature;
    float humidity;
    float light;
    float soil_moisture;
    uint32_t timestamp;
} SensorData;

// 全局变量
SensorData current_data;
UART_HandleTypeDef huart1;

// 函数声明
void SystemClock_Config(void);
void GPIO_Init(void);
void UART_Init(void);
void Sensors_Init(void);
void Read_Sensors(void);
void Send_Data(void);
void Error_Handler(void);

int main(void) {
    // HAL初始化
    HAL_Init();
    
    // 系统时钟配置
    SystemClock_Config();
    
    // 外设初始化
    GPIO_Init();
    UART_Init();
    Sensors_Init();
    
    // 发送启动消息
    UART_SendString("Agricultural Greenhouse Monitoring System Started\r\n");
    
    // 主循环
    while (1) {
        // 读取传感器数据
        Read_Sensors();
        
        // 发送数据
        Send_Data();
        
        // 延迟1秒
        HAL_Delay(1000);
    }
}

void Read_Sensors(void) {
    // 读取温湿度
    if (!DHT_ReadData(&current_data.temperature, &current_data.humidity)) {
        UART_SendString("DHT Error\r\n");
    }
    
    // 读取光照
    current_data.light = Read_Light_Sensor();
    
    // 读取土壤湿度
    current_data.soil_moisture = Read_Soil_Moisture();
    
    // 更新时间戳
    current_data.timestamp = HAL_GetTick();
}

void Send_Data(void) {
    char buffer[256];
    int len = snprintf(buffer, sizeof(buffer),
        "T:%.1f,H:%.1f,L:%.1f,S:%.1f,T:%lu\r\n",
        current_data.temperature,
        current_data.humidity,
        current_data.light,
        current_data.soil_moisture,
        current_data.timestamp
    );
    
    UART_SendString(buffer);
}

void Error_Handler(void) {
    while (1) {
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);
        HAL_Delay(500);
    }
}
```

**光照传感器驱动**

```c
#include "stm32f4xx_hal.h"
#include "adc.h"

ADC_HandleTypeDef hadc1;

void ADC_Init(void) {
    ADC_ChannelConfTypeDef sConfig = {0};
    
    hadc1.Instance = ADC1;
    hadc1.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
    hadc1.Init.Resolution = ADC_RESOLUTION_12B;
    hadc1.Init.ScanConvMode = DISABLE;
    hadc1.Init.ContinuousConvMode = DISABLE;
    hadc1.Init.DiscontinuousConvMode = DISABLE;
    hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
    hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
    hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
    hadc1.Init.NbrOfConversion = 1;
    hadc1.Init.DMAContinuousRequests = DISABLE;
    hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
    
    if (HAL_ADC_Init(&hadc1) != HAL_OK) {
        Error_Handler();
    }
    
    sConfig.Channel = ADC_CHANNEL_0;
    sConfig.Rank = 1;
    sConfig.SamplingTime = ADC_SAMPLETIME_3CYCLES;
    
    if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK) {
        Error_Handler();
    }
}

float Read_Light_Sensor(void) {
    uint32_t adc_value;
    float voltage;
    float light_lux;
    
    // 启动ADC转换
    HAL_ADC_Start(&hadc1);
    
    // 等待转换完成
    if (HAL_ADC_PollForConversion(&hadc1, 100) == HAL_OK) {
        adc_value = HAL_ADC_GetValue(&hadc1);
    } else {
        return 0.0f;
    }
    
    // 停止ADC
    HAL_ADC_Stop(&hadc1);
    
    // 转换为电压
    voltage = (float)adc_value * 3.3f / 4095.0f;
    
    // 转换为光照强度（根据传感器特性）
    light_lux = voltage * 1000.0f;
    
    return light_lux;
}
```

**土壤湿度传感器驱动**

```c
#include "stm32f4xx_hal.h"

#define SOIL_MOISTURE_PIN GPIO_PIN_1
#define SOIL_MOISTURE_PORT GPIOA

float Read_Soil_Moisture(void) {
    uint32_t adc_value;
    float voltage;
    float moisture;
    
    // 配置ADC通道
    ADC_ChannelConfTypeDef sConfig = {0};
    sConfig.Channel = ADC_CHANNEL_1;
    sConfig.Rank = 1;
    sConfig.SamplingTime = ADC_SAMPLETIME_3CYCLES;
    HAL_ADC_ConfigChannel(&hadc1, &sConfig);
    
    // 启动ADC转换
    HAL_ADC_Start(&hadc1);
    
    // 等待转换完成
    if (HAL_ADC_PollForConversion(&hadc1, 100) == HAL_OK) {
        adc_value = HAL_ADC_GetValue(&hadc1);
    } else {
        return 0.0f;
    }
    
    // 停止ADC
    HAL_ADC_Stop(&hadc1);
    
    // 转换为电压
    voltage = (float)adc_value * 3.3f / 4095.0f;
    
    // 转换为湿度百分比
    moisture = (1.0f - voltage / 3.3f) * 100.0f;
    
    // 限制范围
    if (moisture < 0.0f) moisture = 0.0f;
    if (moisture > 100.0f) moisture = 100.0f;
    
    return moisture;
}
```

### 6.2 项目二：智能畜牧养殖管理系统

#### 6.2.1 项目概述
开发一个智能畜牧养殖管理系统，包含动物健康监测、环境控制、数据采集等功能。

#### 6.2.2 核心功能实现

**主程序**

```c
#include "stm32f4xx_hal.h"
#include <string.h>

// 动物数据结构
typedef struct {
    uint8_t id;
    float temperature;
    float heart_rate;
    uint32_t activity_level;
    uint32_t timestamp;
} AnimalData;

// 环境数据结构
typedef struct {
    float temperature;
    float humidity;
    float ammonia;
    uint32_t timestamp;
} EnvironmentData;

// 全局变量
AnimalData animal_data;
EnvironmentData env_data;
UART_HandleTypeDef huart1;

// 函数声明
void System_Init(void);
void Read_Animal_Sensors(void);
void Read_Environment_Sensors(void);
void Control_Environment(void);
void Send_Data(void);
void Error_Handler(void);

int main(void) {
    HAL_Init();
    System_Init();
    
    UART_SendString("Smart Livestock Management System Started\r\n");
    
    while (1) {
        // 读取动物传感器
        Read_Animal_Sensors();
        
        // 读取环境传感器
        Read_Environment_Sensors();
        
        // 控制环境
        Control_Environment();
        
        // 发送数据
        Send_Data();
        
        HAL_Delay(5000);
    }
}

void Read_Animal_Sensors(void) {
    // 读取体温
    animal_data.temperature = Read_Animal_Temperature();
    
    // 读取心率
    animal_data.heart_rate = Read_Heart_Rate();
    
    // 读取活动水平
    animal_data.activity_level = Read_Activity_Level();
    
    // 更新时间戳
    animal_data.timestamp = HAL_GetTick();
}

void Read_Environment_Sensors(void) {
    // 读取环境温度
    env_data.temperature = Read_Environment_Temperature();
    
    // 读取环境湿度
    env_data.humidity = Read_Environment_Humidity();
    
    // 读取氨气浓度
    env_data.ammonia = Read_Ammonia_Level();
    
    // 更新时间戳
    env_data.timestamp = HAL_GetTick();
}

void Control_Environment(void) {
    // 温度控制
    if (env_data.temperature > 28.0f) {
        Turn_On_Fan();
    } else if (env_data.temperature < 20.0f) {
        Turn_Off_Fan();
    }
    
    // 湿度控制
    if (env_data.humidity > 80.0f) {
        Turn_On_Dehumidifier();
    } else if (env_data.humidity < 40.0f) {
        Turn_Off_Dehumidifier();
    }
    
    // 通风控制
    if (env_data.ammonia > 20.0f) {
        Turn_On_Ventilation();
    } else if (env_data.ammonia < 10.0f) {
        Turn_Off_Ventilation();
    }
}

void Send_Data(void) {
    char buffer[256];
    
    // 发送动物数据
    int len = snprintf(buffer, sizeof(buffer),
        "A:%d,T:%.1f,H:%.1f,AL:%lu,T:%lu\r\n",
        animal_data.id,
        animal_data.temperature,
        animal_data.heart_rate,
        animal_data.activity_level,
        animal_data.timestamp
    );
    UART_SendString(buffer);
    
    // 发送环境数据
    len = snprintf(buffer, sizeof(buffer),
        "E,T:%.1f,H:%.1f,NH3:%.1f,T:%lu\r\n",
        env_data.temperature,
        env_data.humidity,
        env_data.ammonia,
        env_data.timestamp
    );
    UART_SendString(buffer);
}
```

**心率传感器驱动**

```c
#include "stm32f4xx_hal.h"

#define HEART_RATE_PIN GPIO_PIN_2
#define HEART_RATE_PORT GPIOA

volatile uint32_t heart_rate_count = 0;
volatile uint32_t last_heart_rate_time = 0;
volatile float heart_rate = 0.0f;

void Heart_Rate_Init(void) {
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    
    // 配置为输入
    GPIO_InitStruct.Pin = HEART_RATE_PIN;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_PULLUP;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(HEART_RATE_PORT, &GPIO_InitStruct);
}

float Read_Heart_Rate(void) {
    static uint32_t last_count = 0;
    static uint32_t last_time = 0;
    uint32_t current_time = HAL_GetTick();
    
    // 计算心率
    if (current_time - last_time >= 1000) {
        uint32_t beat_count = heart_rate_count - last_count;
        heart_rate = (float)beat_count * 60.0f / ((current_time - last_time) / 1000.0f);
        
        last_count = heart_rate_count;
        last_time = current_time;
    }
    
    return heart_rate;
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin) {
    if (GPIO_Pin == HEART_RATE_PIN) {
        heart_rate_count++;
    }
}
```

## 七、测试与调试

### 7.1 单元测试

```c
#include "unity.h"

void test_sensor_reading(void) {
    float temperature, humidity;
    
    // 测试DHT传感器读取
    uint8_t result = DHT_ReadData(&temperature, &humidity);
    
    TEST_ASSERT_EQUAL_UINT8(1, result);
    TEST_ASSERT_FLOAT_WITHIN(1.0f, 25.0f, temperature);
    TEST_ASSERT_FLOAT_WITHIN(10.0f, 50.0f, humidity);
}

void test_i2c_communication(void) {
    uint8_t test_data = 0x55;
    uint8_t read_data;
    
    // 测试I2C写读
    I2C_WriteByte(0x50, 0x00, test_data);
    read_data = I2C_ReadByte(0x50, 0x00);
    
    TEST_ASSERT_EQUAL_UINT8(test_data, read_data);
}

int main(void) {
    UNITY_BEGIN();
    
    RUN_TEST(test_sensor_reading);
    RUN_TEST(test_i2c_communication);
    
    return UNITY_END();
}
```

### 7.2 调试技巧

```c
#include <stdio.h>

// 调试宏定义
#ifdef DEBUG
    #define DEBUG_PRINT(fmt, ...) printf("[DEBUG] " fmt "\r\n", ##__VA_ARGS__)
#else
    #define DEBUG_PRINT(fmt, ...)
#endif

// 错误处理宏
#define CHECK_ERROR(condition, message) \
    if (!(condition)) { \
        DEBUG_PRINT("Error: %s", message); \
        Error_Handler(); \
    }

// 性能测量宏
#define MEASURE_START() uint32_t start_time = HAL_GetTick()
#define MEASURE_END(label) uint32_t end_time = HAL_GetTick(); \
                          DEBUG_PRINT("%s took %lu ms", label, end_time - start_time)

// 使用示例
void example_function(void) {
    MEASURE_START();
    
    // 执行操作
    CHECK_ERROR(operation_success(), "Operation failed");
    
    MEASURE_END("example_function");
}
```

## 八、性能优化

### 8.1 内存优化

```c
// 使用位域节省内存
typedef struct {
    uint8_t id : 5;      // 5位，0-31
    uint8_t type : 3;    // 3位，0-7
    uint8_t status : 2;  // 2位，0-3
    uint8_t reserved : 2; // 2位，保留
} CompactData;

// 使用联合体共享内存
typedef union {
    uint32_t value;
    struct {
        uint8_t byte0;
        uint8_t byte1;
        uint8_t byte2;
        uint8_t byte3;
    } bytes;
} SharedMemory;

// 使用静态内存池
#define POOL_SIZE 10
typedef struct {
    uint8_t data[64];
    uint8_t used;
} MemoryBlock;

MemoryBlock memory_pool[POOL_SIZE];

void* allocate_from_pool(void) {
    for (int i = 0; i < POOL_SIZE; i++) {
        if (!memory_pool[i].used) {
            memory_pool[i].used = 1;
            return memory_pool[i].data;
        }
    }
    return NULL;
}

void free_to_pool(void* ptr) {
    for (int i = 0; i < POOL_SIZE; i++) {
        if (memory_pool[i].data == ptr) {
            memory_pool[i].used = 0;
            return;
        }
    }
}
```

### 8.2 代码优化

```c
// 使用查表替代计算
const uint16_t sine_table[360] = {
    0, 17, 34, 52, 69, 87, 104, 121, 139, 156, 173, 190, 207, 224, 241, 258,
    // ... 更多数据
};

uint16_t fast_sin(uint16_t angle) {
    return sine_table[angle % 360];
}

// 使用位操作替代乘除法
uint32_t multiply_by_8(uint32_t value) {
    return value << 3;  // 等同于 value * 8
}

uint32_t divide_by_8(uint32_t value) {
    return value >> 3;  // 等同于 value / 8
}

// 使用内联函数减少函数调用开销
static inline uint32_t max_value(uint32_t a, uint32_t b) {
    return (a > b) ? a : b;
}

// 使用DMA减少CPU负担
void start_dma_transfer(uint8_t* src, uint8_t* dst, uint16_t length) {
    HAL_DMA_Start_IT(&hdma_memtomem, (uint32_t)src, (uint32_t)dst, length);
}
```

## 九、发布与部署

### 9.1 固件烧录

```bash
# 使用ST-Link烧录
st-flash write firmware.bin 0x8000000

# 使用OpenOCD烧录
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg \
       -c "program firmware.bin verify reset exit"

# 使用J-Link烧录
JLinkExe -device STM32F411RE -if SWD -speed 4000 \
         -autoconnect 1 -CommandFile "flash.jlink"
```

### 9.2 OTA升级

```c
// OTA升级功能
typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t size;
    uint32_t crc;
} FirmwareHeader;

uint8_t check_firmware_validity(uint8_t* firmware_data, uint32_t size) {
    FirmwareHeader* header = (FirmwareHeader*)firmware_data;
    
    // 检查魔数
    if (header->magic != 0x12345678) {
        return 0;
    }
    
    // 检查版本
    if (header->version <= get_current_version()) {
        return 0;
    }
    
    // 检查CRC
    uint32_t calculated_crc = calculate_crc(firmware_data, size);
    if (calculated_crc != header->crc) {
        return 0;
    }
    
    return 1;
}

uint8_t perform_ota_upgrade(uint8_t* firmware_data, uint32_t size) {
    // 检查固件有效性
    if (!check_firmware_validity(firmware_data, size)) {
        return 0;
    }
    
    // 擦除Flash
    if (!erase_application_flash()) {
        return 0;
    }
    
    // 写入新固件
    if (!write_firmware_to_flash(firmware_data, size)) {
        return 0;
    }
    
    // 验证固件
    if (!verify_firmware_in_flash()) {
        return 0;
    }
    
    // 重启系统
    NVIC_SystemReset();
    
    return 1;
}
```

## 十、常见问题与解决方案

### 10.1 内存溢出
**问题**：栈溢出或堆溢出

**解决方案**：
```c
// 增加栈大小
/* 在链接脚本中修改栈大小 */
_stack_size = 0x1000;  // 4KB

// 使用静态分配替代动态分配
static uint8_t buffer[256];

// 检查指针有效性
#define SAFE_FREE(ptr) \
    if (ptr != NULL) { \
        free(ptr); \
        ptr = NULL; \
    }
```

### 10.2 实时性问题
**问题**：中断响应延迟

**解决方案**：
```c
// 提高中断优先级
void configure_interrupt_priority(void) {
    HAL_NVIC_SetPriority(EXTI0_IRQn, 0, 0);  // 最高优先级
    HAL_NVIC_SetPriority(TIM2_IRQn, 1, 0);
    HAL_NVIC_SetPriority(USART1_IRQn, 2, 0);
}

// 减少中断处理时间
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin) {
    // 快速处理
    if (GPIO_Pin == GPIO_PIN_0) {
        flag = 1;
    }
}

// 在主循环中处理耗时操作
void main_loop(void) {
    while (1) {
        if (flag) {
            flag = 0;
            // 耗时处理
            process_event();
        }
    }
}
```

## 十一、学习资源

### 11.1 官方文档
- STM32官方文档：https://www.st.com/resource/en/user_manual/dm00105879.pdf
- ESP32官方文档：https://docs.espressif.com/projects/esp-idf/en/latest/
- Arduino官方文档：https://www.arduino.cc/reference/en/

### 11.2 推荐书籍
- 《嵌入式C语言程序设计》
- 《STM32库开发实战指南》
- 《嵌入式系统设计与实践》

### 11.3 在线课程
- STM32官方教程
- ESP32开发教程
- Arduino项目实战

## 十二、实验项目要求

### 12.1 基础要求
1. 使用C/C++语言开发
2. 采用HAL库或Arduino框架
3. 实现传感器数据采集
4. 实现通信功能（UART、I2C、SPI）
5. 实现基本的控制逻辑
6. 添加单元测试

### 12.2 进阶要求
1. 实现RTOS实时操作系统
2. 集成网络功能（WiFi、MQTT）
3. 优化代码性能和内存使用
4. 实现OTA升级功能
5. 添加低功耗模式
6. 实现故障诊断和恢复

### 12.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
3. 硬件连接图和原理图
4. 测试报告
5. 技术文档和架构设计图