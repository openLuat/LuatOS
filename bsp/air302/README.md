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

Air302专属群: 972784352

## 常用链接

* [合宙官方](http://www.openluat.com)
* [合宙商城](https://m.openluat.com)
* [新手包(含刷机固件,文档,demo)](https://gitee.com/openLuat/LuatOS/releases)
* [API文档](https://gitee.com/openLuat/LuatOS/blob/master/docs/api/lua/README.md)
* [刷机说明@doc](http://doc.openluat.com/article/977/0)
* [刷机说明@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/burn_guide.txt)
* [硬件资源说明@doc](http://doc.openluat.com/article/978/0)
* [硬件资源说明@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/hw_resources.txt)
* [已知限制@doc](http://doc.openluat.com/article/979/0)
* [已知限制@gitee](https://gitee.com/openLuat/LuatOS/blob/master/bsp/air302/userdoc/limits.txt)
* [开发板购买@合宙商城](https://m.openluat.com)
* [开发板购买@骑士智能](https://item.taobao.com/item.htm?id=621910075534)
* [LuatOS源码@gitee](https://gitee.com/openLuat/LuatOS) 期待你的小星星
* [LuatOS源码@github](https://github.com/openLuat/LuatOS) 期待你的小星星
* [demo,长期更新](https://gitee.com/openLuat/LuatOS/tree/master/bsp/air302/demo)
