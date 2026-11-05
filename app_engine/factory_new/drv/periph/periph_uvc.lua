--[[
@module  periph_uvc
@summary UVC 摄像头供电外设驱动（config.peripherals 中 type="uvc"）
@version 1.1
@date    2026.10.23
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明：
   peripherals = {
       { type = "uvc", id = "uvc1", name = "UVC摄像头", en_pin = 58, ready_delay = 200 },
   }
   -- 本板 en_pin 为 GPIO12 且确认该脚独立可控（非 8605 那种 VBUS 共轨）时，须显式声明：
   --    { type = "uvc", id = "uvc1", name = "UVC摄像头", en_pin = 12, ready_delay = 200,
   --      pin12_free = true }

=== 接口 ===

M.init(params)   → handle | false, err
M.list()         → { {id=, name=, handle=}, ... }
M.get(id)        → handle
M.reset_all()    → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()   → ok, err      摄像头供电 + 等待稳定
handle:stop()    → ok           断电
handle:status()  → { enabled=bool, info=string }

=== 约定 ===

- 本驱动是**纯供电驱动**：只控制 en_pin 电平与 ready_delay 稳定延时，
  不调用任何 camera.* —— 数据流（预览/拍照/录像）由 ui/uvc_preview_win.lua
  走 excamera 扩展库独占管理，避免与 camera.init 二次初始化打架
- ready_delay 为供电稳定等待时长（ms），start 拉高 en_pin 后等待；
  仅协程环境下 sys.wait，非协程环境跳过等待
- 供电控制默认禁止使用 GPIO12（8605 等机型上该脚是 VBUS 与 5V_EN 共轨，
  拉低会断触摸供电）；仅当配置显式写 pin12_free = true 时才放开，
  用于 GPIO12 独立做 UVC_EN 的机型（如 Engine_Air8607A）
- 所有 gpio.* 调用 pcall 包裹，失败返回 false + 错误串
]]

local airlink_pin = require "airlink_pin"

local M = {}

-- 已登记实例：id → handle
local instances = {}

-- 等待毫秒，非协程环境跳过
local function wait_ms(ms)
    if not ms or ms <= 0 then return end
    local co = coroutine and coroutine.running and coroutine.running()
    if co == nil then return end
    pcall(sys.wait, ms)
end

-- 设置 GPIO 电平（WiFi 侧脚等 airlink 链路就绪后下发）
local function pin_set(pin, level)
    if not pin then return end
    airlink_pin.set(pin, level)
end

-- 校验使能脚是否允许驱动；pin12_free 未声明时 GPIO12 一律拒绝
local function check_en_pin(p)
    if not p.en_pin then return false, "missing en_pin" end
    if p.en_pin == 12 and not p.pin12_free then
        return false, "en_pin 12 为 VBUS，禁止驱动（如本板该脚独立可控请配 pin12_free = true）"
    end
    return true
end

-- 打开摄像头供电
local function uvc_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end
    local ok, err = check_en_pin(p)
    if not ok then return false, err end
    if self.enabled then return true end

    pin_set(p.en_pin, 1)
    wait_ms(p.ready_delay or 200)

    self.enabled = true
    log.info("periph_uvc", "UVC 供电已打开", self.id, p.en_pin, (p.ready_delay or 200) .. "ms")
    return true
end

-- 断开摄像头供电
local function uvc_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    local p = self.params

    pin_set(p.en_pin, 0)
    self.enabled = false
    log.info("periph_uvc", "UVC 供电已关闭", self.id)
    return true
end

-- 读取状态
local function uvc_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p = self.params or {}
    local name = self.name or p.id or "?"
    local on   = self.enabled and true or false
    local pwr  = on and "供电ON" or "供电OFF"
    return {
        enabled = on,
        info = string.format("%s | %s | GPIO%d | 预览页控制数据流", name, pwr,
                             p.en_pin or 0),
    }
end

-- 创建 handle 并挂载方法
local function make_handle(params)
    local h = {
        id      = params.id,
        name    = params.name or params.id,
        params  = params,
        enabled = false,
    }
    h.start  = uvc_start
    h.stop   = uvc_stop
    h.status = uvc_status
    return h
end

--[[
登记 UVC 实例（不供电）
@param table params  config.peripherals 条目
@return table|false  handle 或 false, 错误串
]]
function M.init(params)
    if type(params) ~= "table" then return false, "params must be table" end
    if not params.id then return false, "missing id" end
    local ok, err = check_en_pin(params)
    if not ok then return false, err end
    if instances[params.id] then return false, "duplicated id: " .. tostring(params.id) end
    local h = make_handle(params)
    instances[params.id] = h
    log.info("periph_uvc", "UVC 已登记", params.id, params.en_pin)
    return h
end

--[[
列出已登记实例
@return table  { {id=, name=, handle=}, ... }
]]
function M.list()
    local out = {}
    for id, h in pairs(instances) do
        out[#out + 1] = { id = id, name = h.name, handle = h }
    end
    return out
end

--[[
取单个实例 handle
@param string id  实例 id
@return table|nil  handle
]]
function M.get(id)
    return instances[id]
end

-- 关闭全部实例并清空注册表
function M.reset_all()
    for id, h in pairs(instances) do
        pcall(h.stop, h)
        instances[id] = nil
    end
    return true
end

return M
