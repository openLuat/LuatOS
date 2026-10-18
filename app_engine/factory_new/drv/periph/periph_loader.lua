--[[
@module  periph_loader
@summary 外设预留框架：按 config.peripherals 声明式列表初始化外设（未实现 type 记日志跳过）
@version 1.0
@date    2026.10.16
@author  江访

=== 使用方式 ===

1. config/eng_xxx.lua 声明 peripherals 列表（声明式，未实现的 type 只登记不动作）：
   peripherals = {
       { type = "uvc",     en_pin = 58, ready_delay = 200 },  -- UVC 摄像头
       { type = "rs485",   en_pins = {14, 65, 49}, uart_id = 11 },
       { type = "spi_cam" },   -- SPI 摄像头（预留）
       { type = "can" },       -- CAN（预留）
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
    -- ["uvc"]     = function(params) return require("periph_uvc").init(params) end,
    -- ["rs485"]   = function(params) return require("periph_rs485").init(params) end,
    -- ["spi_cam"] = function(params) return require("periph_spi_cam").init(params) end,
    -- ["can"]     = function(params) return require("periph_can").init(params) end,
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
