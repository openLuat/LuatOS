--[[
@module  led
@summary 三色LED控制模块（被动控制：AirCloud 云端命令 / Web 页面操作）
@version 1.0
@date    2026.09.24
@author  王城钧
@usage

硬件说明：
  三色 LED 指示灯，红/绿/蓝三路，**互斥点亮（同一时刻只亮一路）**，高电平点亮
      红 = GPIO27，绿 = GPIO28，蓝 = GPIO26
  （与产测模式指令 LED_TEST,{R|G|B|0}# 使用的引脚完全一致）

模块定位：
  本模块为**被动控制模块**，不包含任何自动灯效。
  原先的自动指示逻辑（温湿度更新绿灯脉冲、从站收到请求红灯）已全部移除；
  LED 仅在收到 AirCloud 云端命令或 Web 页面操作时才点亮，上电默认全灭。

对外接口：
  led.set_color(color)  -- color: "red"/"green"/"blue"/"off"（不区分大小写），成功返回 true，参数非法返回 false
  led.off()             -- 全灭（等价于 led.set_color("off")）
  led.get_state()       -- 回读当前点亮颜色："red"/"green"/"blue"/"off"

调用说明：
  本文件没有主动对外消息接口，直接在 main.lua 中 require "led" 即可加载；
  控制入口统一调用 led.set_color。
  本模块仅使用 gpio.set，不含 sys.wait，可在 C 层回调（AirCloud 命令回调、HTTP 回调）中直接调用。
]]

local led = {}

local PINS = {27, 28, 26}  -- RED=GPIO27, GREEN=GPIO28, BLUE=GPIO26

-- 颜色名 → PINS 下标
local COLOR_INDEX = {
    red   = 1,
    green = 2,
    blue  = 3,
}

-- 当前点亮颜色（初始全灭）
local current_color = "off"

-- 全部熄灭
local function off_all()
    for _, p in ipairs(PINS) do gpio.set(p, 0) end
end

-- 设置颜色（三路互斥，同一时刻只亮一路）
-- @param color string "red"/"green"/"blue"/"off"（不区分大小写）
-- @return boolean 成功 true；参数非法 false
function led.set_color(color)
    if type(color) ~= "string" then return false end
    local name = string.lower(color)
    if name == "off" or name == "none" then
        off_all()
        current_color = "off"
        return true
    end
    local idx = COLOR_INDEX[name]
    if not idx then return false end
    off_all()                       -- 互斥：先全灭，再点亮目标色
    gpio.set(PINS[idx], 1)
    current_color = name
    return true
end

-- 全部熄灭
-- @return boolean 恒为 true
function led.off()
    return led.set_color("off")
end

-- 回读当前点亮颜色
-- @return string "red"/"green"/"blue"/"off"
function led.get_state()
    return current_color
end

-- 初始化：三路配置为推挽输出、默认全灭
for _, p in ipairs(PINS) do
    gpio.setup(p, 0, gpio.PULLDOWN)
end
off_all()

return led