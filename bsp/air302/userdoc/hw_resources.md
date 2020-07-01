# Air302 硬件资源说明

## 管脚映射表

管脚编号对应w600芯片的管脚编号, 与GPIO编号有对应关系, 请查阅Air302硬件设计手册

## 关于ADC

1. ADC0 实际上对应通道2, 读取时应使用 `adc.read(2)`. 
2. 通道0为CPU温度, 通道1为VBAT电压.

## 关于 AON_GPIO

1. AON_GPIO2 对应 GPIO24 `gpio.setup(24,0)`
2. AON_GPIO3 对应 GPIO23 `gpio.setup(23,0)`

## 关于SPI

1. SPI功能暂不可用(截止到20200627,尚未支持)
