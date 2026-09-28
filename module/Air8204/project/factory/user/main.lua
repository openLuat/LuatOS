--[[
@module  main
@summary Air8204 出厂固件入口（产测 + 出货合一）
@version 1.0
@date    2026.09.28
@usage
本文件为 Air8204 出厂固件的程序入口，遵循解耦设计规范：
main.lua 仅包含 PROJECT / VERSION / PRODUCT_KEY 常量定义、require 与 sys.run()，
不包含任何功能代码；启动初始化与产测/出货分流全部由 boot.lua 实现。

固件形态：产测 + 出货合一（单工程、单入口）
  - 产测标记 test_done 未完成 → boot.lua 加载 factory.lua 进入产测模式
  - 产测标记 test_done 已完成 → boot.lua 加载 card_main.lua 进入出货模式（air_card 应用）

硬件说明：
本固件运行于 Air8204（智能录音定位工牌 PCBA），其通信定位部分基于合宙 Air780EGH 模组，
录音部分基于顺芯 ES7243E，运动检测部分基于明皜 DA221，因此引脚定义文件沿用
pins_Air780EGH.json（LuaTools 依据模组型号 Air780EGH 识别引脚映射）。
]]

--[[
必须定义 PROJECT 和 VERSION 变量，LuaTools 工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string 类型，可以随便定义，只要不使用就行
VERSION：项目版本号，ascii string 类型
        如果使用合宙 iot.openluat.com 进行远程升级，必须按照 "XXX.YYY.ZZZ" 三段格式定义：
            X、Y、Z 各表示 1 位数字，因为历史原因，YYY 这三位数字必须存在，但没有任何用处
]]
PROJECT = "Air8204_Factory"
-- iot 限制，只能上传 xxx.yyy.zzz 格式的三位数字版本号；因 yyy 不生效，建议中间一位永远写 000
VERSION = "001.000.001"

--[[
PRODUCT_KEY：合宙 IoT 平台（iot.openluat.com）产品密钥，仅用于整机成品 FOTA（libfota3）。
注意：与基站定位（airlbs）的 project_key（见 lbs_util.lua）不是同一个，请勿混用。
客户提供真实 KEY 前保持占位符；update.lua 会自动识别占位符并跳过 FOTA，避免无效连接。
]]
PRODUCT_KEY = "YOUR_PRODUCT_KEY_HERE"

-- 启动引导：fskv 初始化 / VREF 拉高 / 软狗启动 / FOTA 启动 / 产测与出货分流
require "boot"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
