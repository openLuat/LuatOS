--[[
@module  periph_loader
@summary 外设预留框架：按 config.peripherals 声明式列表初始化外设（未实现 type 记日志跳过）
@version 1.0
@date    2026.10.16
@author  江访

=== 使用方式 ===

1. config/eng_xxx.lua 声明 peripherals 列表（声明式，未实现的 type 只登记不动作）：
   peripherals = {
       { type = "uvc", id = "uvc1", name = "USB摄像头", en_pin = 58, ready_delay = 200,
         w = 960, h = 480 },  -- USB 摄像头（en_pin 可选）
       { type = "rs485",   en_pins = {14, 65, 49}, uart_id = 11 },
       { type = "spi_cam" },   -- SPI 摄像头（预留）
       { type = "onewire" },   -- 1-Wire（预留）
   }

2. 实现驱动：新建 drv/periph/periph_<type>.lua，导出 init(params) → handle|false

3. 在 PERIPH_REGISTRY 注册一行：
   ["uvc"] = function(params) return require("periph_uvc").init(params) end,
   注意：驱动是动态 require（闭包内），编译系统文本扫描不到，
   实现后需把 periph_<type> 登记进 platform_loader 编译清单

=== 约定 ===

- 稳定延时写条目里（ready_delay，ms），loader 在 init 前等待（谁用谁等）
- 未注册的 type 记日志跳过：配置先行、实现后补，互不阻塞
- 事件命名沿用工程约定：<TYPE>_READY / <TYPE>_<ACTION>_REQ / <TYPE>_<ACTION>_RSP
- 由 app_main.optional 调用 init_all，处于协程环境，可安全 sys.wait
]]

local M = {}

-- 外设驱动注册表：type → 初始化函数（按需 require 对应驱动，未注册=预留未实现）
local PERIPH_REGISTRY = {
    ["uvc"]     = function(params) return require("periph_uvc").init(params) end,
    ["rs485"]   = function(params) return require("periph_rs485").init(params) end,
    -- GNSS 没有开机初始化动作：UART3 与 GNSS 供电都由 exgnss 在页面打开时才动，
    -- 开机就去开串口反而会和 4G/网络初始化抢 UART3。这里只返回 true 标记「已就绪」
    -- （非 nil 即视为就绪），既不执行动作也不打「预留未实现」的日志。
    -- 实际取参仍由 settings_gnss_app 从 config.peripherals 查（与 rs485 同一套路）；
    -- 不要把 params 原样返回 —— 那会让 p.handle 指向 p 自身，留下自引用。
    ["gnss"]    = function(params) return true end,
    -- 蓝牙同理：exril_5101 在页面打开时才 config_uart / 切 AT 模式，
    -- 开机就去开 UART3 会和 4G 抢串口。这里只返回 true 标记「已就绪」。
    -- 供电脚 en_pin（BLE_EN=GPIO47）也不在此驱动：config.power_on 开机先拉低，
    -- settings_ble_app 进页面拉高（等 boot_delay）、退出拉低，与 GNSS_EN 一致。
    ["ble"]     = function(params) return true end,
    -- CAN 是内置核心库，不进本框架：开机不碰总线（CAN2 复用 UART2，会和 RS485 抢串口），
    -- 参数直接读 config.can，由 settings_can_app 在进页面时才 init。
    -- ["spi_cam"] = function(params) return require("periph_spi_cam").init(params) end,
    -- ["onewire"] = function(params) return require("periph_onewire").init(params) end,
}

--[[
按 config.peripherals 逐个初始化外设
@param table peripherals  config.peripherals 配置列表（可为 nil）
]]
function M.init_all(peripherals)
    if type(peripherals) ~= "table" then return end
    for i, p in ipairs(peripherals) do
        local ptype = p and p.type
        local factory = ptype and PERIPH_REGISTRY[ptype]
        if factory then
            if p.ready_delay and p.ready_delay > 0 then
                sys.wait(p.ready_delay)
            end
            local ok, handle = pcall(factory, p)
            if ok and handle then
                p.handle = handle
                log.info("periph_loader", "外设就绪", ptype)
            else
                log.warn("periph_loader", "外设初始化失败", ptype, handle)
            end
        else
            log.info("periph_loader", "外设预留未实现，跳过", ptype or ("#" .. i))
        end
    end
end

return M
