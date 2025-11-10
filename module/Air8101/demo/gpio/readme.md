## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统并启动各个GPIO功能任务；

2、gpio_output_task.lua：GPIO输出模式功能模块，演示GPIO输出控制方法；

3、gpio_input_task.lua：GPIO输入模式功能模块，演示GPIO输入读取方法；

4、gpio_pull_task.lua：GPIO上拉下拉模式功能模块，演示GPIO上拉下拉配置；

5、gpio_irq_task.lua：GPIO中断(触发)模式功能模块，演示GPIO中断触发、回调处理及按键短按长按检测；

6、gpio_irqcount_task.lua：GPIO中断(计数)模式功能模块，演示GPIO中断计数功能；

7、agpio_task.lua：AGPIO功能模块，演示低功耗GPIO在休眠模式下的特性；

8、gpio_toggle_task.lua：GPIO翻转测速功能模块，演示GPIO脉冲输出功能；



## 演示功能概述

1、gpio_output_task：GPIO输出模式功能演示
- 配置GPIO5为输出模式，通过GPIO5输出高低电平
- 可使用万用表测量验证GPIO5的电平变化
- 以1000ms间隔切换电平状态，便于观察
- 演示gpio.setup的输出模式配置和状态控制方法

2、gpio_input_task：GPIO输入模式功能演示
- 配置GPIO7为输入模式，配置GPIO5为输出模式
- 实现输入信号读取，并将读取到的电平状态同步控制GPIO5
- 演示gpio.debounce防抖功能的使用
- 展示如何通过输入GPIO的状态控制输出GPIO

3、gpio_pull_task：GPIO上拉下拉模式功能演示
- 配置GPIO5为上拉输入模式，GPIO6为下拉输入模式
- 演示gpio.debounce防抖功能在不同上下拉模式下的应用
- 通过定时任务周期性读取并打印GPIO的当前电平状态
- 展示如何使用gpio.get函数获取GPIO的实时状态

4、gpio_irq_task：GPIO中断(触发)模式功能演示
- 配置GPIO5为中断模式，支持上升沿和下降沿触发（双边沿触发）
- 实现中断触发时的回调函数，打印触发信息
- 演示gpio.debounce防抖功能在中断模式下的应用
- 实现按键短按(小于3秒)和长按(大于等于3秒)的检测功能
- 可连接按键或直接用杜邦线轻触GND进行测试

5、gpio_irqcount_task：GPIO中断(计数)模式功能演示
- 配置GPIO5为中断计数模式，用于统计信号触发次数
- 配置PWM4输出1kHz、占空比50%的方波作为计数信号源
- 实现周期性（1秒）统计和打印中断触发次数
- 展示gpio.count函数在计数模式下的使用方法

6、该模块暂不包含AGPIO功能演示

7、gpio_toggle_task：GPIO翻转测速功能演示
- 配置GPIO5为输出模式，初始电平为低电平
- 演示gpio.pulse函数生成指定模式的电平变化序列
- 输出8组电平变化（0xA9，即二进制10101001）
- 展示如何通过快速电平翻转实现特定信号模式的输出

## 演示硬件环境

1、Air8101核心板一块：
- 确保核心板正常供电

2、USB数据线一根，Air8101核心板和数据线的硬件接线方式为：
- Air8101核心板通过USB口供电；
- USB数据线直接插到核心板的USB座子，另外一端连接电脑USB口；

3、可选硬件（根据需要）：
- 外部按键或信号源：用于GPIO输入模式和中断模式的信号输入测试
- 面包板、杜邦线：用于连接外部信号源和核心板GPIO

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 版本固件](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

在main.lua中，可以根据需要启用或禁用特定的GPIO功能任务：
- 通过注释或取消注释相应的require语句来控制功能模块的加载
- 每个功能模块作为独立的任务运行，可以单独测试或组合测试

### 1、GPIO输出模式
1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "gpio_output_task"`这一行
3. 将代码下载到核心板并运行
4. **演示效果**：GPIO5将按照设定的时间间隔交替输出高电平和低电平，可使用万用表测量验证

### 2、GPIO输入模式
1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "gpio_input_task"`这一行语句
3. 将代码下载到核心板并运行
4. **演示效果**：当GPIO7输入为高电平时，GPIO5会输出高电平；当GPIO7输入为低电平时，GPIO5会输出低电平

### 3、GPIO上拉下拉模式
1. 搭建好硬件环境
2. 打开main.lua，确保只保留`require "gpio_pull_task"`这一行语句
3. 将代码下载到核心板并运行
4. **演示效果**：串口日志中会周期性显示GPIO5（上拉输入）和GPIO6（下拉输入）的当前电平状态

### 4、GPIO中断(触发)模式
1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "gpio_irq_task"`这一行语句
3. 将代码下载到核心板并运行
4. **演示效果**：当GPIO5的电平发生变化时，会触发中断并检测按键动作，在串口日志中打印短按(小于3秒)或长按(大于等于3秒)事件

### 5、GPIO中断(计数)模式
1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "gpio_irqcount_task"`这一行语句
3. 将代码下载到核心板并运行
4. **演示效果**：PWM4输出方波信号到GPIO5，串口日志中每秒显示一次中断触发的计数值

### 6、该模块暂不包含AGPIO功能演示

### 7、GPIO翻转测速
1. 搭建好硬件环境
2. 打开main.lua，确保保留`require "gpio_toggle_task"`这一行语句
3. 将代码下载到核心板并运行
4. **演示效果**：GPIO5会根据gpio.pulse函数的配置快速输出特定模式的电平变化序列（二进制10101001），通过示波器或逻辑分析仪等工具可以查看示例效果展示
