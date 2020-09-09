# Air302 硬件资源说明

## 关于ADC

1. ADC0 实际上对应通道2, 读取时应使用 `adc.read(2)`. 
2. 通道0为CPU温度, 通道1为VBAT电压.

## 关于 AON_GPIO

1. AON_GPIO2 对应 GPIO22 `gpio.setup(22,0)`
2. AON_GPIO3 对应 GPIO24 `gpio.setup(24,0)`
