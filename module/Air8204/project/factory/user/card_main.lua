--[[
@module  card_main
@summary 出货模式装配入口（由原 air_card/main.lua 改造）
@version 1.0
@date    2026.09.28
@usage
由 boot.lua 在「已完成产测」时 require，装配 air_card 全量业务应用：
录音（ES7243E）+ 卫星/基站双模定位（GNSS + airlbs）+ 云接入（excloud）
+ TF 卡存储 + 震动检测（DA221）+ 状态灯（WS2812）+ 电量检测。

与改造前（air_card/main.lua）的差异：
  1. 去除 PROJECT / VERSION 常量与 sys.run()（已上移到 main.lua / boot.lua）
  2. 去除 fskv / VREF(GPIO23) / wdt / FOTA 启动代码（已上移到 boot.lua）
  3. 去除 fota.lua 的加载（OTA 统一由 update.lua + libfota3 管理）
  4. 保留既有全局变量加载方式（excloud / libnet / config / led_util / lbs_util /
     gps / http_app / RecordingManager / gpio_utils），以保证各模块间既有引用关系不变

模块加载顺序（依赖自底向上，业务调度 app 最后加载）：
  mem_monitor → network_watchdog → excloud / libnet / config → excloud_app → sd_test
  → gpio_util → lbs_util → normal → http_app → es7243e → led_util → da221 → app
]]

-- 系统监控与服务
require "mem_monitor"       -- 内存监控（周期性打印内存使用，辅助定位内存泄漏）
require "network_watchdog"  -- 网络业务看门狗（超时软件重启）

-- 云平台与全局配置（全局变量，供各功能模块跨文件引用）
excloud = require("excloud")
libnet = require "libnet"
config = require "config"

-- 业务功能模块
require "excloud_app"                  -- AirCloud 云平台接入（连接认证 / TLV 上报 / 下行命令 / 心跳 / 运维日志）
RecordingManager = require "sd_test"   -- 录音存储库（TF 卡挂载 + 录音元数据库 + 上传状态机）
gpio_utils = require "gpio_util"       -- 电池电量检测 + 录音开关检测
lbs_util = require "lbs_util"          -- 基站/WiFi（airlbs）混合定位
gps = require "normal"                 -- GNSS 卫星定位
http_app = require "http_app"          -- 录音文件上传
require "es7243e"                      -- ES7243E 录音驱动（I2C 配置 + I2S 采集）
led_util = require "led_util"          -- 双路 WS2812 状态灯
require "da221"                        -- DA221 运动检测（动态开关定位省电）

-- 业务调度（最后加载，内部启动周期上报与上传轮询任务）
require "app"

return "card_main"
