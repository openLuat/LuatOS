# Air302@LuatOS

## Air302是什么?

合宙Air302, 是基于移芯EC616的NB-IOT模块, 封装尺寸兼容合宙Air202,功能管脚基本上一一对应.

## LuatOS为它提供哪些功能

* 192kb的系统内存, 可用内存约30kb
* 78kb的Lua专属内存,可用内存约50kb
* 文件系统大小332kb,格式littlefs 2.1,可用空间约200kb
* 基于Lua 5.3.6, 提供95%的原生库支持
* 适配LuaTask,提供极为友好的`sys.lua`
* `gpio` GPIO管脚控制功能(映射表后面有提供)
* `uart` 串口输入输出功能,支持uart1(调试/刷机)/uart2(用户可用)/uart0(芯片日志)
* `i2c` iic总线master功能
* `disp` 基于i2c的显示屏支持,当前支持SSD1306
* `nbiot` 与nbiot相关的支持
* `json` lua对象与json字符串的双向转换
* `socket` 异步Socket接口,用于与服务器的通信
* `log` 简洁的日志功能
* `libcoap` coap消息处理所需方法
* `libgnss` GPS/北斗等NMEA数据的处理
* `mqtt` 连接到mqtt服务器的功能,结合`crypto`加密库,可连接到阿里云
* `pwm` 多个PWM输出管脚,存在复用关系
* `adc` 外部电平检测,内部温度检测,供电电压检测
* `pm` 低功耗管理

LuatOS大QQ群: 1061642968

## 管脚映射表

| 管脚编号 | 命名   | 默认功能          |
| -------- | ------ | ----------------- |
| 1        | GPIO1  | BOOT              |
| 2        | GPIO16 | SPI_CS            |
| 3        | GPIO15 | SPI_CLK           |
| 4        | GPIO11 | SPI_MOSI          |
| 5        | GPIO14 | SPI_MISO          |
| 6        | GPIO9  | GPIO              |
| 7        | GPIO7  | GPIO              |
| 8        | GPIO12 | UART1_TX(打印Log) |
| 9        | GPIO13 | UART1_RX(打印Log) |
| 12       | -      | WAKEUP_IN         |
| 13       | GPIO19 | NET_LED           |
| 14       | ADC0   | ADC               |
| 16       | GPIO23 | AON_GPIO_4        |
| 17       | GPIO21 | AON_GPIO_2        |
| 18       | GPIO18 | GPIO              |
| 19       | GPIO17 | GPIO              |
| 25       | GPIO4  | UART0_TX          |
| 26       | GPIO5  | UART0_RX          |
| 27       | GPIO2  | UART2_RX          |
| 28       | GPIO3  | UART2_TX          |
| 29       | GPIO8  | I2C0_SDA          |
| 30       | GPIO10 | I2C0_SCL          |

ADC

| ADC编号（LuatOS） | 功能     |
| ----------------- | -------- |
| 0                 | CPU温度  |
| 1                 | VBAT电压 |
| 2                 | 模块ADC0 |



## 常用链接

* [合宙官方](http://www.openluat.com)
* [合宙商城](https://m.openluat.com)
* [新手包(含刷机固件,文档,demo)](https://gitee.com/openLuat/LuatOS/releases)
* [API文档](https://gitee.com/openLuat/LuatOS/blob/master/docs/api/lua/README.md)
* [刷机说明@doc](http://doc.openluat.com/article/977/0)
* [刷机说明@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/burn_guide.md)
* [硬件资源说明@doc](http://doc.openluat.com/article/978/0)
* [硬件资源说明@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/hw_resources.md)
* [已知限制@doc](http://doc.openluat.com/article/979/0)
* [已知限制@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/limits.md)
* [开发板购买@合宙商城](https://m.openluat.com)
* [LuatOS源码@gitee](https://gitee.com/openLuat/LuatOS) 期待你的小星星
* [LuatOS源码@github](https://github.com/openLuat/LuatOS) 期待你的小星星
* [demo,长期更新](https://gitee.com/openLuat/LuatOS/tree/master/bsp/air302/demo)
