
## 演示功能概述

本demo使用Air780EGH核心板，演示GPIO接口功能测试，包括GPIO的输入输出，中断检测/中断计数，翻转速度，上下拉测试与AGPIO测试

## 演示硬件环境

1、Air780EHM核心板一块，TYPE-C USB数据线一根

2、LED模块一个，独立按键模块一个，杜邦线若干

3、合宙IOTpower 或 Air9000功耗分析仪 一台

4、逻辑分析仪 或 示波器 一台

5、万用表一台

4、不同测试的引脚硬件连接介绍

1）GPIO输出测试(gpio_output_test)：(PIN16)GPIO27 外接LED模块

2）GPIO输入测试(gpio_input_test): (PIN16)GPIO27 外接LED模块, (PIN20)GPIO24 杜邦线连接电源3.3V或GND

3）GPIO中断输入测试(gpio_irq_test): (PIN20)GPIO24 杜邦线连接电源3.3V或GND

4）GPIO中断计数测试(gpio_irq_count_test): (PIN16)PWM4 通过杜邦线与(PIN20)GPIO24相连接

5）GPIO翻转速度测试(gpio_toggle_test): (PIN16)GPIO27 连接示波器或逻辑分析仪

6）GPIO上拉下拉测试(gpio_pullupdown_test): (PIN56)GPIO07用于上拉输入，(PIN16)GPIO27用于下拉输入

7）AGPIO测试(apio_test):  (PIN22)GPIO01, (PIN16)GPIO27 测试时分别连接示波器，核心板USB旁边的开关拨到off一端, Vbat连接合宙IOTpower或Air9000的"+", GND连接合宙IOTpower或Air9000的"-",合宙IOTpower或Air9000设置3.8V供电打开

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2007版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2007固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，不同测试结果描述如下，具体详见相关文档 [Air780EGH GPIO](https://docs.openluat.com/air780egh/luatos/app/driver/gpio/)

1）GPIO输出测试(gpio_output_test)：LED模块500ms输出高电平点亮LED，500ms输出低电平熄灭LED，循环执行这个流程

2）GPIO输入测试(gpio_input_test): 获取GPIO24电平状态，为高则LED点亮，为低则LED熄灭

3）GPIO中断输入测试(gpio_irq_test): GPIO24杜邦线连接电源3.3V或GND，luatools中都会打印 "被触发" 的字段

4）GPIO中断计数测试(gpio_irq_count_test): luatools中会打印测试结果

> I/user irq count 2000  
> I/user irq count 1999  
> I/user irq count 2001  

5）GPIO翻转速度测试(gpio_toggle_test): 逻辑分析仪或示波器测量(PIN16)GPIO27的IO高低电平变化 40-50ns左右

6）GPIO上拉下拉测试(gpio_pullupdown_test): luatools中会打印测试结果

> I/user GPIO  7 电平 1  
> I/user GPIO  27 电平 0  

7）AGPIO测试(apio_test):  正常工作模式，万用表测量(PIN22)GPIO01、(PIN16)GPIO27电平都为3.0V，进入低功耗模式时万用表测量(PIN22)GPIO01为0V, (PIN16)GPIO27保持3.0V不变
