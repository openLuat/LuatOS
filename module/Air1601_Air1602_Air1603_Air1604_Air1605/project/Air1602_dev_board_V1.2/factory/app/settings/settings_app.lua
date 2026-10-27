
--[[
@module  settings_app
@summary 设置模块主入口
@version 1.0
@date    2026.04.02
@author  江访
@usage
本模块为设置功能的主入口，负责：
1. 通知 settings_config_app 进行初始化
2. 协调各个设置子模块的加载
]]
local fe = (_G.project_config and _G.project_config.features) or {}

require "settings_config_app"   -- fskv配置管理（设备名称、IOT账号、存储优先级读写）
require "settings_channel_app"  -- UART3 口复用配置（4G/WiFi/GNSS/蓝牙 四选一，fskv 持久化）
if fe.buzzer then
    require "settings_buzz_app"     -- 触摸音效管理（仅当有蜂鸣器）
end
require "settings_about_app"    -- 关于页面信息
require "settings_display_app"  -- 亮度与声音管理（PWM 背光 + 媒体音量）
require "settings_storage_app"  -- 存储空间信息查询（内置Flash）
if fe.sd_card or fe.nand_flash then
    require "storage_pri_app"       -- 外部存储初始化（仅当有SD卡/NAND Flash）
end
require "settings_memory_app"   -- 系统内存/Vm/PSRAM 信息查询
if fe.rs485 then
    require "settings_rs485_app"    -- RS485 收发测试（config.peripherals 声明，取用时才查驱动表）
end
if fe.uvc then
    require "settings_uvc_app"      -- USB 摄像头数据流（开流/关流，画面由 UI 的 airui.camera 显示）
end
if fe.gnss then
    require "settings_gnss_app"     -- GNSS 定位（exgnss + config.peripherals 的 gnss 条目）
end
if fe.ble then
    require "settings_ble_app"      -- 蓝牙测试（exril_5101 + config.peripherals 的 ble 条目，用 UART3）
end
require "settings_can_app" -- CAN 总线测试（内置 can 库，参数取 config.can，本板 CAN2 复用 UART2）
require "settings_auto_app" -- 后装APP开机自启管理（fskv 持久化 + 密码验证 + NES_CTRL 退出拦截）
sys.publish("SETTINGS_APP_INIT")  -- 等待fskv就绪后再发布 SETTINGS_APP_INIT 事件，确保配置模块先行初始化
