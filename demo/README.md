# LuatOS 演示代码

## 重要提示

库的demo通常都需要配合最新的固件, 如果发现demo有问题, 请先确认是不是最新固件.

最新固件下载地址: https://gitee.com/openLuat/LuatOS/releases

## demo的适用性

* 如果有子文件夹, 例如Air101, 代表该demo可能只适合对应的硬件使用. 但Air101/Air103/W806属于同一类型, 基本通用.
* 不带子文件的,通常是通用demo, 与具体硬件无关, 但使用的固件可能不带对应的库, 就会提示xxx not found 或者 nil xxx

## Demo列表

* esp32c3的配网相关的demo 请查阅 [wlan](wlan/) 目录

|文件名|功能|依赖的库|受支持的模块|备注|
|------|----|-------|-----------|----|
|[adc](https://gitee.com/openLuat/LuatOS/tree/master/demo/adc/)|模数转换|adc|所有||
|[camera](https://gitee.com/openLuat/LuatOS/tree/master/demo/camera/)|摄像头|camera|air105||
|[coremark](https://gitee.com/openLuat/LuatOS/tree/master/demo/coremark/)|跑分|coremark|所有|生产固件均不带该库,可自行编译或云编译|
|[crypto](https://gitee.com/openLuat/LuatOS/tree/master/demo/crypto/)|加解密|crypto|所有||
|[dht12](https://gitee.com/openLuat/LuatOS/tree/master/demo/dht12/)|温湿度传感器|i2c|所有||
|[eink](https://gitee.com/openLuat/LuatOS/tree/master/demo/eink/)|电子墨水屏|eink|所有||
|[fatfs](https://gitee.com/openLuat/LuatOS/tree/master/demo/fatfs/)|挂载sd卡|fatfs,sdio|所有|部分模块支持sdio挂载,其余支持spi挂载|
|[fdb](https://gitee.com/openLuat/LuatOS/tree/master/demo/fdb/)|持久化kv存储|fdb|所有||
|[fs](https://gitee.com/openLuat/LuatOS/tree/master/demo/fs/)|文件系统|io|所有||
|[gpio](https://gitee.com/openLuat/LuatOS/tree/master/demo/gpio/)|通用输入输出|gpio|所有||
|[gpio_irq](https://gitee.com/openLuat/LuatOS/tree/master/demo/gpio_irq/)|io中断|gpio|所有||
|[gtfont](https://gitee.com/openLuat/LuatOS/tree/master/demo/gtfont/)|高通字体|gtfont|所有|需要额外的高通字体芯片,外挂在SPI|
|[hello_world](https://gitee.com/openLuat/LuatOS/tree/master/demo/hello_world/)|最简示例|无|所有||
|[i2c](https://gitee.com/openLuat/LuatOS/tree/master/demo/i2c/)|IIC总线|i2c|所有|演示i2c基本操作|
|[io_queue](https://gitee.com/openLuat/LuatOS/tree/master/demo/io_queue/)|IO序列|ioqueue|air105|高精度IO序列|
|[ir](https://gitee.com/openLuat/LuatOS/tree/master/demo/ir/)|红外|ir|air105|当前仅支持接收|
|[json](https://gitee.com/openLuat/LuatOS/tree/master/demo/json/)|JSON编解码|json|所有||
|[keyboard](https://gitee.com/openLuat/LuatOS/tree/master/demo/keyboard/)|键盘矩阵|keyboard|air105|硬件直驱|
|[lcd](https://gitee.com/openLuat/LuatOS/tree/master/demo/lcd/)|SPI屏驱|lcd,spi|所有||
|[lcd_custom](https://gitee.com/openLuat/LuatOS/tree/master/demo/lcd_custom/)|自定义LCD屏驱|lcd,spi|所有|自定义LCD驱动|
|[lcd_mlx90640](https://gitee.com/openLuat/LuatOS/tree/master/demo/lcd_mlx90640/)|红外测温|mlx90640|所有|未完成|
|[libcoap](https://gitee.com/openLuat/LuatOS/tree/master/demo/libcoap/)|coap编解码|licoap|所有|仅编解码,不含通信|
|[libgnss](https://gitee.com/openLuat/LuatOS/tree/master/demo/libgnss/)|GNSS解析|libgnss|所有|通过UART与GNSS模块通信|
|[lvgl](https://gitee.com/openLuat/LuatOS/tree/master/demo/lvgl/)|LVGL示例|lvgl,spi|所有|该目录下有大量LVGL实例,不同模组的实例也能参考|
|[meminfo](https://gitee.com/openLuat/LuatOS/tree/master/demo/meminfo/)|内存状态|rtos|所有||
|[multimedia](https://gitee.com/openLuat/LuatOS/tree/master/demo/multimedia/)|多媒体|decoder|air105|音频解码示例|
|[network](https://gitee.com/openLuat/LuatOS/tree/master/demo/network/)|网络库|network|air105|与w5500配合,实现以太网访问|
|[nimble](https://gitee.com/openLuat/LuatOS/tree/master/demo/nimble/)|蓝牙库|nimble|air101/air103|仅支持简单收发,功耗高|
|[ota](https://gitee.com/openLuat/LuatOS/tree/master/demo/ota/)|固件更新|uart|自带网络的请使用libfota库,参考fota的demo||
|[pm](https://gitee.com/openLuat/LuatOS/tree/master/demo/pm/)|功耗控制|pm|所有||
|[pwm](https://gitee.com/openLuat/LuatOS/tree/master/demo/pwm/)|可控方波|pwm|所有||
|[rtc](https://gitee.com/openLuat/LuatOS/tree/master/demo/rtc/)|内部时钟|rtc|所有||
|[sdcard](https://gitee.com/openLuat/LuatOS/tree/master/demo/sdcard/)|挂载SD卡|spi,sdio|air101|与fatfs类似|
|[sfud](https://gitee.com/openLuat/LuatOS/tree/master/demo/sfud/)|通用FLASH读写|sfud,spi|所有||
|[sht20](https://gitee.com/openLuat/LuatOS/tree/master/demo/sht20/)|温湿度传感器|i2c|所有||
|[sht30](https://gitee.com/openLuat/LuatOS/tree/master/demo/sht30/)|温湿度传感器|i2c|所有||
|[socket](https://gitee.com/openLuat/LuatOS/tree/master/demo/socket/)|网络套接字|socket|air105/air780e||
|[spi](https://gitee.com/openLuat/LuatOS/tree/master/demo/spi/)|SPI库演示|spi|所有||
|[statem](https://gitee.com/openLuat/LuatOS/tree/master/demo/statem/)|io状态机|statem|所有|air105推荐用ioqueue|
|[sys_timerStart](https://gitee.com/openLuat/LuatOS/tree/master/demo/sys_timerStart/)|演示定时运行|sys|所有||
|[u8g2](https://gitee.com/openLuat/LuatOS/tree/master/demo/u8g2/)|单色OLED屏驱|u8g2|所有||
|[uart](https://gitee.com/openLuat/LuatOS/tree/master/demo/uart/)|UART演示|uart|所有||
|[usb_hid](https://gitee.com/openLuat/LuatOS/tree/master/demo/usb_hid/)|USB自定义HID|usbapp|air105||
|[usb_tf](https://gitee.com/openLuat/LuatOS/tree/master/demo/usb_tf/)|USB读写TF卡|usbapp|air105|速度500~700kbyte/s|
|[usb_uart](https://gitee.com/openLuat/LuatOS/tree/master/demo/usb_uart/)|USB虚拟串口|usbapp|air105||
|[video_play](https://gitee.com/openLuat/LuatOS/tree/master/demo/video_play/)|视频播放|uart,sdio|所有|当前仅支持裸rgb565ble视频流|
|[wdt](https://gitee.com/openLuat/LuatOS/tree/master/demo/wdt/)|硬狗|wdt|所有||
|[ws2812](https://gitee.com/openLuat/LuatOS/tree/master/demo/ws2812/)|驱动WS2812B|gpio,pwm,spi|所有||
|[wlan](https://gitee.com/openLuat/LuatOS/tree/master/demo/wlan/)|wifi相关|wlan|ESP32系列支持wifi,Air780E系列只支持wifi扫描||

