--[[
@module  periph_uvc
@summary UVC 摄像头供电外设驱动（config.peripherals 中 type="uvc"）
@version 1.2
@date    2026.11.06
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明：
   peripherals = {
       { type = "uvc", id = "uvc1", name = "UVC摄像头", en_pin = 58, ready_delay = 200 },
   }
   -- 摄像头常供电、无独立使能脚时省掉 en_pin（本驱动不动任何 GPIO）：
   --    { type = "uvc", id = "uvc1", name = "UVC摄像头", ready_delay = 200 }
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
- en_pin 可省略：摄像头常供电（无独立使能脚）时不写，驱动全程不动 GPIO，
  start/stop 只登记开关状态
- ready_delay 为供电稳定等待时长（ms），start 拉高 en_pin 后等待；
  仅协程环境下 sys.wait，非协程环境跳过等待
- 供电控制默认禁止使用 GPIO12（8605 等机型上该脚是 VBUS 与 5V_EN 共轨，
  拉低会断触摸供电）；仅当配置显式写 pin12_free = true 时才放开，
  用于 GPIO12 独立做 UVC_EN 的机型（如 Engine_Air8607A）
- **en_pin 与别的外设 de_pin 共用一脚时**（8603W3~W5 / M3~M5 的 GPIO58 = UVC_EN = 485_EN2），
  经 pin_share 按职能互斥认领：start 认领（把还挂着该脚的 485 路停干净再供电）、stop 归还，
  两个功能相互切换、互不影响；上电稳定等待期间被别的职能切走时本次 start 作废返回 false
- 所有 gpio.* 调用 pcall 包裹，失败返回 false + 错误串
]]

local airlink_pin = require "airlink_pin"
local pin_share = require "pin_share"

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

-- 校验使能脚是否允许驱动；en_pin 缺省即摄像头常供电
-- pin12_free 未声明时 GPIO12 一律拒绝
local function check_en_pin(p)
    if not p.en_pin then return true end
    if p.en_pin == 12 and not p.pin12_free then
        return false, "en_pin 12 为 VBUS，禁止驱动（如本板该脚独立可控请配 pin12_free = true）"
    end
    return true
end

-- 共享 en_pin 被别的职能（如 485_EN2 的 DE）切走时的交接回调：
-- 用到该脚的全部实例就地标记断电（含上电稳定等待中的），脚电平归新主管，这里不再动
local function uvc_lost(pin)
    for _, h in pairs(instances) do
        if h.enabled and h.params and h.params.en_pin == pin then
            h.enabled = false
            log.info("periph_uvc", "UVC_EN 脚已切给其它职能，供电交出", h.id, "GPIO" .. tostring(pin))
        end
    end
end

-- 打开摄像头供电
local function uvc_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end
    local ok, err = check_en_pin(p)
    if not ok then return false, err end
    if self.enabled then return true end

    -- 先挂牌再等稳定：等待期间被别的职能切走时 uvc_lost 能停到它，等完再复核认领
    self.enabled = true
    if p.en_pin then
        local owner = "uvc:" .. tostring(self.id)
        pin_share.claim(p.en_pin, "uvc_en", owner, uvc_lost)
        pin_set(p.en_pin, 1)
        wait_ms(p.ready_delay or 200)
        if pin_share.role(p.en_pin) ~= "uvc_en" then
            self.enabled = false
            return false, "GPIO" .. tostring(p.en_pin) .. " 已切给其它职能，UVC 供电未生效"
        end
    end

    log.info("periph_uvc", "UVC 供电已打开", self.id, p.en_pin or "常供电", (p.ready_delay or 200) .. "ms")
    return true
end

-- 断开摄像头供电
local function uvc_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    local p = self.params

    self.enabled = false
    if p.en_pin then
        -- 还握着这根脚才动电平：中途被别的职能切走时电平已归新主管
        if pin_share.role(p.en_pin) == "uvc_en" then
            pin_set(p.en_pin, 0)
        end
        pin_share.release(p.en_pin, "uvc:" .. tostring(self.id))
    end
    log.info("periph_uvc", "UVC 供电已关闭", self.id)
    return true
end

-- 读取状态
local function uvc_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p   = self.params or {}
    local name = self.name or p.id or "?"
    local on   = self.enabled and true or false
    local pwr  = on and "供电ON" or "供电OFF"
    local pin  = p.en_pin and ("GPIO" .. p.en_pin) or "常供电"
    return {
        enabled = on,
        info = string.format("%s | %s | %s | 预览页控制数据流", name, pwr, pin),
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
    log.info("periph_uvc", "UVC 已登记", params.id, params.en_pin or "常供电")
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
