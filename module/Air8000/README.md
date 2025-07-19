# LuatOS-Air780EPM

## 介绍

本代码库 是 合宙 Air780EPM 模组的代码中心, 包括演示代码demo, 案例代码project等

如需查阅文档, 请访问合宙文档中心的[Air780EPM模块文档中心](https://docs.openluat.com/air780epm/)

## 目录说明

* demo  [演示代码](demo/)
* project  [案例代码](project/)

## 固件说明

1. Air780EPM 只有1种32位固件，没有64位固件；

2. Air780EHM，Air780EHV，Air780EGH 当前有22种固件，32位和64位各11种;

3. 关于差分升级的相关说明；

差分升级只能在同类固件之间进行，

固件1 只能差分升级为固件1，

固件2 只能差分升级为固件2，

固件X 只能差分升级为固件X。## 固件说明

1. Air780EPM 只有1种32位固件，没有64位固件；

2. Air780EHM，Air780EHV，Air780EGH 当前有22种固件，32位和64位各11种;

3. 关于差分升级的相关说明；

差分升级只能在同类固件之间进行，

固件1 只能差分升级为固件1，

固件2 只能差分升级为固件2，

固件X 只能差分升级为固件X。

![输入图片说明](LuatOS%E5%A4%9A%E5%9B%BA%E4%BB%B6%E7%AD%96%E7%95%A5%E8%AF%B4%E6%98%8E.png)

![输入图片说明](LuatOS%E5%A4%9A%E5%9B%BA%E4%BB%B6%E5%8A%9F%E8%83%BD%E5%8C%BA%E5%88%AB.png)

![输入图片说明](LuatOS%E6%89%A9%E5%B1%95%E5%BA%93%E7%AE%80%E8%A6%81%E8%AF%B4%E6%98%8E.png)

## demo使用说明

[**JT808**]：本demo演示使用string.pack与unpack函数，实现JT808 终端注册协议数据生成与解析，适用于车辆定位和监控系统。

[**Websocket**]：本demo演示使用websocket协议，实现LuatOS与Web服务器的通信，适用于实时数据传输和双向通信场景。

[**adc**]：本demo演示LuatOS的ADC功能，用于模拟信号的读取，适用于传感器数据采集等场景。

[**airlbs**]：本demo演示LuatOS的LBS功能，包括多基站定位和WIFI定位，适用于位置服务开发。

[**bit**]：本demo演示LuatOS的bit操作功能，适用于需要进行位级操作的场景。

[**bit64**]：本demo演示LuatOS的64位bit操作功能，适用于需要进行大范围位级操作的场景。

[**camera/spi_cam**]：本demo演示LuatOS的SPI摄像头功能，适用于需要集成摄像头进行图像采集的设备。

[**can**]：本demo演示LuatOS的CAN总线通信功能，适用于汽车电子和工业自动化等场景。

[**crypto**]：本demo演示LuatOS的加密功能，包括哈希、对称加密和非对称加密等，适用于需要进行数据加密和解密的场景。

[**errdump**]：本demo演示LuatOS的错误信息转储功能，适用于设备调试和错误分析。

[**fota2**]：本demo演示LuatOS的FOTA（空中下载）功能，包括固件更新等，适用于设备远程升级和维护。

[**fs**]：本demo演示LuatOS的文件系统功能，包括文件读写等，适用于需要进行文件存储和操作的场景。

[**gpio**]：本demo演示LuatOS的GPIO功能，包括数字输入输出等，适用于需要进行硬件控制的场景。

[**helloworld**]：本demo演示LuatOS的基本运行环境，通过输出“Hello, World!”来验证开发环境是否搭建成功。

[**hmeta**]：本demo演示LuatOS的硬件信息查询功能，适用于获取设备硬件相关信息。

[**http**]：本demo演示LuatOS的HTTP协议功能，包括网页请求和文件下载等，适用于需要进行网络通信的场景。

[**i2c-sht20**]：本demo演示LuatOS的I2C通信功能，通过SHT20温湿度传感器来读取温度和湿度信息。

[**iconv**]：本demo演示LuatOS的字符编码转换功能，适用于需要进行字符编码转换的场景。

[**iotcloud**]：本demo演示LuatOS与物联网云平台的通信，包括设备连接、数据上传和云服务调用等。

[**json**]：本demo演示LuatOS的JSON数据解析和生成功能，适用于需要进行JSON格式数据处理的场景。

[**lbsloc2**]：本demo演示LuatOS的LBS定位功能，适用于需要进行精准位置定位的场景。

[**lcd**]：本demo演示LuatOS的LCD显示功能，适用于需要进行图形界面显示的设备。

[**log**]：本demo演示LuatOS的日志记录功能，适用于需要进行日志记录和分析的场景。

[**lowpower**]：本demo演示LuatOS的低功耗模式功能，适用于需要进行设备功耗优化的场景。

[**miniz**]：本demo演示LuatOS的压缩和解压缩功能，适用于需要进行数据压缩和解压缩的场景。

[**mobile**]：本demo演示LuatOS的移动网络功能，包括蜂窝网络连接、数据传输等，适用于需要进行移动网络通信的场景。

[**mqtt**]：本demo演示LuatOS的MQTT协议功能，适用于物联网场景下的消息发布和订阅。

[**netdrv/ch390**]：本demo演示LuatOS与CH390芯片的网络驱动功能，适用于USB转网口的设备。

[**ntp**]：本demo演示LuatOS的NTP网络时间同步功能，适用于需要进行时间同步的场景。

[**onewire**]：本demo演示LuatOS的1-Wire协议功能，适用于连接单总线设备如DS18B20温度传感器等。

[**openai/deepseek**]：本demo演示LuatOS如何集成OpenAI的DeepSeek服务，适用于需要进行深度学习推理的场景。

[**pack**]：本demo演示LuatOS的数据打包和解包功能，适用于需要进行数据格式转换的场景。

[**protobuf**]：本demo演示LuatOS的protobuf数据解析和生成功能，适用于需要进行protobuf格式数据处理的场景。

[**pwm**]：本demo演示LuatOS的PWM功能，适用于需要进行脉冲宽度调制的场景。

[**sms**]：本demo演示LuatOS的短信收发功能，适用于嵌入式设备需要进行短信通信的场景。

[**spi**]：本demo演示LuatOS的SPI通信功能，适用于需要进行SPI通信的场景。

[**string**]：本demo演示LuatOS的字符串操作功能，包括字符串拼接、分割、查找等，适用于需要进行字符串处理的场景。

[**tcp**]：本demo演示LuatOS的TCP协议功能，适用于需要进行TCP通信的场景。

[**timer**]：本demo演示LuatOS的定时器功能，包括单次定时器和周期定时器，适用于需要定时执行任务的场景。

[**uart**]：本demo演示LuatOS的UART串口通信功能，适用于需要进行串口通信的场景。

[**udp**]：本demo演示LuatOS的UDP协议功能，适用于需要进行UDP通信的场景。

[**wdt**]：本demo演示LuatOS的看门狗定时器功能，适用于需要进行设备监控和自动复位的场景。

[**wlan/wifiscan**]：本demo演示LuatOS的Wi-Fi扫描功能，适用于需要搜索和连接Wi-Fi网络的场景。

## 授权协议

[MIT License](LICENSE)

```lua
print("感谢您使用LuatOS ^_^")
print("Thank you for using LuatOS ^_^")
```

