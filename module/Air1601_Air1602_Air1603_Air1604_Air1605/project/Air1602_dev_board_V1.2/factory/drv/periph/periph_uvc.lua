--[[
@module  periph_uvc
@summary USB 摄像头（UVC）外设驱动（config.peripherals 中 type="uvc"，支持多路）
@version 1.1
@date    2026.10.26
@author  江访

=== 配置示例 ===

config/evb_xxx.lua 声明（同一 type 可多条，靠 id 区分）：
   peripherals = {
       -- Air1601 V1.1：USB 口 5V 就是 GPIO12（5V_EN），与 RS485 方向脚复用但两者不同时
       -- 使用，故当可控供电脚用（只拉高 + ready_delay，不掉电）
       -- 注意：power_cycle 别开 —— 重新枚举的时机由调用方控制，必须在
       --   excamera.preview 注册完回调**之后**调 h.recycle(h)；在这里开会让 start()
       --   抢在注册前就把枚举触发掉，回调永远收不到 EV_CONNECT
       { type = "uvc", id = "uvc1", name = "USB摄像头",
         en_pin = 12, pin12_free = true, ready_delay = 200, power_hold = true,
         w = 960, h = 480 },
       -- 摄像头有独立供电脚时：只拉高、退出即断电
       --   { type = "uvc", id = "uvc2", name = "USB摄像头2", en_pin = 58, ready_delay = 200 },
   }

=== 接口 ===

M.init(params)   → handle | false, err
M.list()         → { {id=, name=, handle=}, ... }
M.get(id)        → handle
M.reset_all()    → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()   → ok, err      供电（power_cycle 时先掉电再上电）+ 等待稳定
handle:stop()    → ok           断电（power_hold 为真时只标记，不拉低）
handle:status()  → { enabled=bool, info=string }

=== 约定 ===

- 本驱动只管**供电脚与参数**，不碰任何 camera.* / excamera.*：
  数据流（开流 / 预览 / 关流）由 app/settings/settings_uvc_app.lua 独占管理，
  避免与 excamera.open 里的 camera.init 二次初始化打架
- en_pin 缺省即「底板常供」，start 不动任何 GPIO
- GPIO12 默认**禁止**当 en_pin（它是 USB VBUS / 5V_EN / 6205 EN，误拉低会连带掐掉
  触摸屏与 5V 轨上其它负载）；只有配置显式写 pin12_free = true 才放行，
  由配置方确认该机型上它与 RS485 方向脚不同时使用
- power_cycle = true：start 时先把 en_pin 拉低 cycle_low_ms 毫秒再拉高，
  给摄像头一次真正的掉电重上电。这一项是「有时连不上」的关键 ——
  单纯 gpio.set(1) 对已经高电平的脚不产生边沿，USB 主机不会重新枚举，
  而掉电再上电必然触发 hub 上报 port change → 重新枚举
- power_hold = true 表示该脚还给别的外设供 5V（PA / 6205 / 外挂模组），stop 时只置标志
  不拉低，否则退出一次摄像头页就会把同一路 5V 上的外设一起掐掉
- w / h 是**首选分辨率**，不是强制值：实际开流档位由固件枚举摄像头能力后决定
  （见 settings_uvc_app 的 pick_uvc_mode）。max_pixels 是像素上限，超过的档位不取，
  防止 1920×1080 把内存吃光
- 所有 gpio.* 调用 pcall 包裹，失败返回 false + 错误串
]]

local M = {}

-- 已登记实例：id → handle
local instances = {}

-- 等待毫秒，非协程环境跳过
local function wait_ms(ms)
    if not ms or ms <= 0 then return end
    if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then return end
    pcall(sys.wait, ms)
end

-- 设置 GPIO 电平
local function pin_set(pin, level)
    if not pin then return end
    pcall(gpio.setup, pin, level)
    pcall(gpio.set, pin, level)
end

--[[校验供电脚是否允许驱动：GPIO12 是共用 5V 轨，未显式声明 pin12_free 一律拒绝]]
local function check_en_pin(p)
    if not p or not p.en_pin then return false, "missing en_pin" end
    if p.en_pin == 12 and not p.pin12_free then
        return false, "en_pin 12 为共用 5V 轨，禁止驱动（确认与 RS485 不同时使用时请配 pin12_free = true）"
    end
    return true
end

--[[给摄像头一次真正的掉电重上电：拉低 cycle_low_ms 再拉高，然后等 ready_delay
单纯拉高对已经是高电平的脚不产生边沿，USB 主机不会重新枚举；掉电再上电必然触发
hub 上报 port change → 重新枚举，这是「摄像头连不上」最有效的手段。
拉低期间该脚上其它 5V 负载（PA / 6205）会一起掉电，故时长要短（默认 300ms）。
内部含 sys.wait，必须在协程里调。]]
local function power_cycle_up(self)
    local p = self.params
    local low_ms = math.floor(tonumber(p.cycle_low_ms) or 300)
    if low_ms < 50 then low_ms = 50 end
    if low_ms > 3000 then low_ms = 3000 end
    pin_set(p.en_pin, 0)
    wait_ms(low_ms)
    log.info("periph_uvc", "UVC 掉电重上电", self.id, "GPIO" .. tostring(p.en_pin),
             "拉低", low_ms .. "ms")
    pin_set(p.en_pin, 1)
    wait_ms(p.ready_delay or 200)
end

--[[打开摄像头供电（只拉高；配了 power_cycle 则先掉电再上电）]]
local function uvc_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end

    if p.en_pin then
        local ok, err = check_en_pin(p)
        if not ok then return false, err end

        if p.power_cycle then
            power_cycle_up(self)
        else
            pin_set(p.en_pin, 1)
            wait_ms(p.ready_delay or 200)
        end
    end

    self.enabled = true
    log.info("periph_uvc", "UVC 已打开", self.id,
             p.en_pin and ("GPIO" .. tostring(p.en_pin)) or "供电由底板常供")
    return true
end

--[[强制掉电重上电（不管有没有配 power_cycle），给 USB 主机一次重新枚举

与 uvc_start 里那段的区别在「什么时候调」：**必须在 excamera.preview 注册完回调之后**。
excamera.preview 只靠 usb.EV_CONNECT 事件、不查设备是否已连着，而它上电后只等 100ms
就注册（它假设枚举要 1~2 秒）。本设备的枚举实测只要 ~70ms —— 若在 preview 之前就
把枚举触发掉，回调注册时事件早已发过，永远等不到连接（页面一直卡在「等待摄像头连接」）。
放在 preview 之后调，设备的断开→重连一定被回调看见。]]
local function uvc_recycle(self)
    local p = self and self.params
    if not p or not p.en_pin then return false, "no en_pin（底板常供，无法掉电重上电）" end
    local ok, err = check_en_pin(p)
    if not ok then return false, err end

    power_cycle_up(self)
    self.enabled = true
    log.info("periph_uvc", "UVC 已重新上电", self.id, "GPIO" .. tostring(p.en_pin))
    return true
end

-- 断开摄像头供电（power_hold 的脚只置标志不拉低）
local function uvc_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    local p = self.params

    if p.en_pin and not p.power_hold then
        pin_set(p.en_pin, 0)
    end
    self.enabled = false
    log.info("periph_uvc", "UVC 已关闭", self.id,
             (p.en_pin and not p.power_hold) and "已断电" or "供电保持")
    return true
end

-- 读取状态
local function uvc_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p = self.params or {}
    local pwr = p.en_pin and (self.enabled and "供电ON" or "供电OFF") or "底板常供"
    if p.en_pin and p.power_cycle then pwr = pwr .. " | 开页重上电" end
    return {
        enabled = self.enabled and true or false,
        info = string.format("%s | %s | %dx%d@%d", self.name or p.id or "?", pwr,
                             p.w or 0, p.h or 0, p.fps or 0),
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
    h.start   = uvc_start
    h.stop    = uvc_stop
    h.status  = uvc_status
    h.recycle = uvc_recycle   -- preview 注册回调之后强制重新枚举
    return h
end

--[[
登记 UVC 实例（不开流、不动 GPIO）
@param table params  config.peripherals 条目
@return table|false  handle 或 false, 错误串
]]
function M.init(params)
    if type(params) ~= "table" then return false, "params must be table" end
    if not params.id then return false, "missing id" end
    -- 配了供电脚才校验；不写 en_pin 即底板常供，驱动全程不动 GPIO
    if params.en_pin then
        local ok, err = check_en_pin(params)
        if not ok then return false, err end
    end
    if instances[params.id] then return false, "duplicated id: " .. tostring(params.id) end
    local h = make_handle(params)
    instances[params.id] = h
    log.info("periph_uvc", "UVC 已登记", params.id,
             "USB" .. tostring(params.usb_port or 1),
             tostring(params.w or "-") .. "x" .. tostring(params.h or "-"))
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
