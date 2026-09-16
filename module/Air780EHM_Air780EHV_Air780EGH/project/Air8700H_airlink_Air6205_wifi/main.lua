--[[
@module  main
@summary Air8700H通过SPI连接Air6205创建WiFi热点+Web配置
@version 1.0
@date    2026.09.14
@author  江访
@usage
本demo演示的核心功能为：
1、Air8700H通过Airlink SPI连接Air6205 WiFi模块，创建WiFi热点
2、默认热点名称：luatos_ + IMEI后4位，无密码
3、手机连接热点后访问 http://192.168.4.1/config 配置WiFi和串口参数
4、配置参数保存到flash，重启后自动加载

硬件接线（Air8700H → Air6205）：
| Air8700H引脚 | Air6205引脚 | 功能 |
|-------------|------------|------|
| SPI0_CLK    | SPI_CLK    | SPI时钟 |
| SPI0_MOSI   | SPI_MOSI   | SPI主出从入 |
| SPI0_MISO   | SPI_MISO   | SPI主入从出 |
| GPIO8       | CS         | SPI片选 |
| GPIO33      | RDY        | 就绪信号 |
| GPIO24      | IRQ        | 中断信号 |
| GPIO32      | RST        | WiFi模块复位 |
| GND         | GND        | 共地 |

使用说明：
1、Air8700H烧录本demo固件，Air6205烧录airlink SPI从机固件
2、按上表连接硬件，上电后Air6205自动创建WiFi热点
3、手机连接热点，浏览器访问 http://192.168.4.1/config 进行配置
4、修改WiFi名称/密码/串口波特率后点击保存，配置自动写入flash
--]]

PROJECT = "Air8700H_airlink_Air6205_wifi"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 看门狗初始化
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 加载业务模块
require "config"
require "airlink_wifi_ap"
require "http_config"

-- 启动主任务
require "app_main"

sys.run()
