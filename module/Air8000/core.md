# 最新版本

2025/7/19
 
[LuatOS-SoC_V2010_Air8000](https://cdn6.vue2.cn/Luat_tool_src/v2tools/LuatOS_Air8000/LuatOS-SoC_V2010_Air8000.zip)

1. add: 101-111号固件, 64bit固件

2. add: 支持长短信发送

3. add: gtfont支持到192号字体, 支持灰度

4. change: pins,luatos下默认不打印映射关系的日志,可以通过pins.debug(true)打开日志

5. change: log,重大调整,print/log输出字符串时,改成用单个空格,替代原本的tab

6. change: net_lwip2,每个网卡都使用自身的dns客户端,独立设置自己的dns服务器

7. fix: littlt flash库,优化flash探测方式，兼容不同批次nand

8. 1号~11号为32位固件，101号~111号固件为64位固件，64位相对32位固件新增支持了大数运算，其余相同。

# 历史版本
#### 2025.07.09

根据不同的核心库功能，拆分组合成多个固件，通过固件名称后的数字区分。具体每个固件的功能可参考固件版本对应关系的表格。

[Air8000_1-11_20250709.zip](https://docs.openluat.com/cdn2/tmp/Air8000_1-11_20250709.zip)

1. 修复airtalk通话会死机的问题。
2. 修复pins配置拦截gpio > 128和uartid >= 10 出错。
3. 修复使用pm.power打开GPS供电会导致i2c0通讯有问题。


#### 2025.07.07

根据不同的核心库功能，拆分组合成多个固件，通过固件名称后的数字区分。具体每个固件的功能可参考固件版本对应关系的表格。

[Air8000_1-11_20250707.zip](https://docs.openluat.com/cdn2/tmp/Air8000_1-11_20250707.zip)

1. 修复ftp,在wifi环境下无法使用。
2. 修复蓝牙write发送数据死机。
3. 修复ch390不能复用一个spi的问题。
4. 添加支持SFUD库
5. 添加支持airtalk库
6. 添加支持U8G2库
7. 修复Air8000A不会自启动airlink

#### 2025.06.27

[LuatOS-SoC_V2008_Air8000_LVGL_0627](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_LVGL_0627.soc)

[LuatOS-SoC_V2008_Air8000_VOLTE_0627](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_VOLTE_0627.soc)

[LuatOS-SoC_V2008_Air8000_FS_0627](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_FS_0627.soc)

1. http请求没有加回调函数时添加asset异常提示。
2. 修复FS版本使用vsim功能出现死机的问题。
3. 修复蓝牙连接后有概率出现死机的问题。
4. 蓝牙功能目前已实现主机模式（扫描+主动连接），从机模式（广播+被动连接），仅广播（典型应用ibeacon），仅观察（扫描）
5. 支持httpdns指定adapter网络适配器id，使用不同的网络进行请求。
6. 修复tcs3472，读不到元器件时返回空数据，会报错。

#### 2025.06.23

[LuatOS-SoC_V2008_Air8000_LVGL_0623](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_LVGL_0623.soc)

[LuatOS-SoC_V2008_Air8000_VOLTE_0623](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_VOLTE_0623.soc)

[LuatOS-SoC_V2008_Air8000_FS_0623](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_FS_0623.soc)

1. VOLTE固件 修复接收短信死机和电信卡只能接收一条短信的问题。
2. 修复无法控制GPIO141。

#### 2025.06.21

[LuatOS-SoC_V2008_Air8000_LVGL_0621](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_LVGL_0621.soc)

[LuatOS-SoC_V2008_Air8000_FS_0621](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2008_Air8000_FS_0621.soc)

1. 目前可支持ble低功耗蓝牙广播、从机模式、扫描蓝牙功能。（当前的蓝牙api功能仍处于调试阶段，后续可能还会对api做改动）
2. gpio.get接口支持获取>128gpio输入输出模式的电平状态。
3. 添加airlink.power接口，可控制wifi供电和运行状态。
4. 修复sms.send发送超长短信会死机。限制短信发送长度超过140字节，会直接拒绝发送。
5. 修复Air8000G读不到充电ic。
6. fs 兼容a+b模式打开文件。
7. 支持wifi进入休眠 light和deep模式。
8. 支持使用pm.wakeupPin接口配置唤醒wifi休眠的gpio。

#### 2025.06.10

[LuatOS-SoC_V2007_Air8000_LVGL_0610](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_LVGL_0610.soc)

[LuatOS-SoC_V2007_Air8000_VOLTE_0610](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_VOLTE_0610.soc)

[LuatOS-SoC_V2007_Air8000_FS_0610](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_FS_0610.soc)

#### 2025.06.07

[LuatOS-SoC_V2007_Air8000_LVGL_0607](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_LVGL_0607.soc)

[LuatOS-SoC_V2007_Air8000_VOLTE_0607](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_VOLTE_0607.soc)

#### 2025.06.04

[LuatOS-SoC_V2007_Air8000_LVGL_0604](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_LVGL_0610.soc)

[LuatOS-SoC_V2007_Air8000_VOLTE_0604](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_VOLTE_0604.soc)

#### 2025.05.27

[LuatOS-SoC_V2007_Air8000_LVGL_0527](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_LVGL_0527.soc)

[LuatOS-SoC_V2007_Air8000_VOLTE_0527](https://docs.openluat.com/cdn2/Air8000/LuatOS-SoC_V2007_Air8000_VOLTE_0527.soc)


