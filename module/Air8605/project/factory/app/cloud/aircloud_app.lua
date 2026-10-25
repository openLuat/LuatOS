--[[
@module  aircloud_app
@summary AirCloud 通用数据上报模块（能力探测型 · 不绑定具体型号）
@version 1.2.0
@date    2026.09.23
@author  江访

=== 设计要点 ===

1. 【通用能力探测】不判断芯片型号，运行时用 type(fn) == "function" / pcall 探测
   每个 Lua API 是否存在；存在就采集，不存在就跳过该字段。同一份代码可在
   Air1601 / Air1602 / Air1780 / Air8101 / Air780E / PC 模拟器上运行。

2. 【独立超时保护】耗时项各自单独探测 + 单独超时窗口，任一失败/超时只跳过自己，
   不拖累整轮上报。

3. 【TLV 组装先判空】excloud.build_tlv 遇到 nil / 非 number 会返回 false，
   进而导致 excloud.send 整体失败。所以所有字段必须先算出值、判有效再 push。

4. 【注意】excloud.DATA_TYPES / excloud.FIELD_MEANINGS 是在 excloud.lua
   文件末尾（2368/2369 行）才挂到模块表上的，业务代码只能写
   excloud.DATA_TYPES.XXX，不能用局部名。

5. 【注意】新版 excloud.setup() 会忽略 protocol_version / device_type 参数
   （内部用 get_device_type() 自动识别），所以这里不传。

6. 【注意】PC 模拟器（rtos.bsp() == "PC" → device_type 9）必须提供
   virtual_phone_number，否则 setup() 拿不到 device_id。

7. 【致命陷阱 · 已在真机踩过】绝不能在模块顶层 `require "lbsLoc2"`！
   lbsLoc2.lua 第 90 行（顶层作用域）直接执行：
       lbsLoc2.imei = numToBcdNum(mobile.imei())
   而本模块由 app_main 在**开机瞬间**加载，此刻 Airlink（Air1601 外挂 WiFi/4G）
   通道尚未建立，mobile.imei() 返回 nil → numToBcdNum 内 inStr:len() 索引 nil
   → 整机重启。真机日志特征：
       E/airlink send2transport: mode 2 无 cmd_queue
       E/airlink.rpc rpc: send2transport failed -2
       E/main /luadb/lbsLoc2.luac:-1: attempt to index a nil value
       E/main Lua VM exit!! reboot in 15000ms
   （2026-09-22 起基站定位整体下线，本模块不再 require lbsLoc2，此坑留档备查；
   若将来恢复定位，仍须走「惰性 require + pcall」。）
   ⚠️ 同理适用于任何"文件顶层就调用运行时 API"的库 —— 加 require 前先看它顶层干了什么。

8. 【陷阱 · 真机踩过】excloud 的 INTEGER / FLOAT 全是 **uint32 大端**编码
   （INTEGER = floor(v)，FLOAT = floor(v*1000)），负数一律溢出成补码乱数据
   （to_big_endian 只打告警不拦）。所以：
   - 拒绝一切负值/超界值（push_tlv 统一把关）；
   - 需要负值语义的字段就地偏移（WiFi RSSI 上报 rssi+100）；
   - CPU 温度下界判 `<= 0`（真机噪声 -0.001℃ 也要挡掉）。

9. 【陷阱 · 真机踩过】excloud.start_heartbeat(interval, custom_data) 的载荷
   **不能为空**：不传时内部 `heartbeat_data = custom_data or {}`，
   空 TLV 被 send 拒绝（"没有有效的TLV数据可发送"）→ 心跳一直失败 → 平台判离线。
   必须传非空 TLV 列表（本模块用 设备ID + 固件版本 静态载荷）。

10. 【产品决策 · 2026-09-22】Air1601/Air8601 已核实**不支持** CPU 温度与基站定位：
   - CH_CPU 虚拟通道未实现（仅物理 ADC1/2/5/6，见 demo test_adc.lua），
     adc.get 恒返回 -1（读取失败码）→ 曾产生 -0.001℃ 假温度；
   - WiFi 版外挂 Air6205 无蜂窝，LBS 基站定位无从谈起。
   故本模块只上报**基本信息 + 下行数据交互**，ENV_TEMPERATURE(263) 与
   GNSS 经纬度(512/513) 采集代码已删除，勿再加回。

=== 上报字段（能采就采）===

  设备ID    DEVICE_ID(798)             ASCII   多源 fallback
  固件版本  FIRMWARE_VERSION(1027)     ASCII   VERSION 全局变量
  信号强度  SIGNAL_STRENGTH_4G(782)    INTEGER mobile.csq()
  网络类型  NETWORK_TYPE(781)          INTEGER 探测结果 1=WiFi 2=4G 3=以太网
  SIM卡     SIM_ICCID(783)             ASCII   mobile.iccid()
  电池电量  BATTERY_LEVEL(771)         INTEGER 缓存 BATTERY_STATUS
  电池电压  VOLTAGE(799)               FLOAT   缓存 BATTERY_STATUS
  时间戳    TIMESTAMP(1280)            INTEGER os.time()
  开机原因  BOOT_REASON(776)           INTEGER rtos.rebootReason()
  开机次数  BOOT_COUNT(777)            INTEGER fskv 累计
  内存占用  LUA_MEM_CURRENT_USED(1034) INTEGER rtos.meminfo("lua")
  WiFi-RSSI 1295(自定义)               INTEGER wlan.getInfo().rssi + 100 偏移

  （CPU温度 263 / 经纬度 512/513 已于 2026-09-22 下线，见第 10 条）

=== 下行命令（CONTROL_COMMAND tag 19 · ASCII）===

  cycle:180        改写上报周期（秒，夹到 min_cycle 以上），存 fskv
  backlight:60     调屏幕背光（10~100），转 DISPLAY_BRIGHTNESS_SET 事件
  led:on/off/blink LED 控制（本机无 LED 硬件映射，广播 LED_CONTROL 事件 + 回复 web）
  report:once      立即触发一轮上报
  report:on/off    开关上报
  status           读取当前上报状态（走 CONTROL_RESPONSE 回复）
  tts:<文本>       TTS 语音播报（ASCII 文本直发；含中文会被云端消毒成 '?'，走 ttshex:）
  ttshex:<hex>     TTS 语音播报（UTF-8 文本的十六进制编码，web 端走这条，中文无损）
                   两者均 ≤300 字节文本；无音频能力 hw.audio 的板子回 ERR no audio
  ttsstop          停止当前 TTS 播报

=== 对外事件 ===

  发布  AIRCLOUD_REPORT_RESULT  { success, time, count, err }   上报结果
  发布  AIRCLOUD_STATUS_RESP    {...}                            状态查询应答
  发布  AIRCLOUD_ENABLE_CHANGED bool                              开关变化
  发布  LED_CONTROL            "on"/"off"/"blink"                  LED 下行控制
  订阅  AIRCLOUD_SET_CYCLE      number                          设置页改周期
  订阅  AIRCLOUD_SET_ENABLE     bool                            设置页开关
  订阅  AIRCLOUD_REPORT_NOW                                      设置页立即上报
  订阅  AIRCLOUD_GET_STATUS                                      设置页查状态
  订阅  BATTERY_STATUS          table                           白嫖 battery_app 的电池数据
]]

local excloud = require "excloud"
-- 基站定位已于 2026-09-22 整体下线（见头部第 10 条），本模块**不再使用 lbsLoc2**。
-- 若将来恢复：绝不能在顶层 require（其顶层执行 mobile.imei() 会炸库整机重启，
-- 真机日志特征 E/main /luadb/lbsLoc2.luac:-1: attempt to index a nil value，
-- 见头部第 7 条），只能「用到时惰性 require + pcall 保护」。

-- ==================== 常量 ====================

local APP_VERSION      = "1.2.0"
local FSKV_CYCLE_KEY   = "aircloud_report_cycle"   -- 上报周期（秒）
local FSKV_ENABLE_KEY  = "aircloud_report_enable"  -- 上报总开关
local FSKV_BOOTCNT_KEY = "aircloud_boot_count"     -- 开机次数累计
local DEFAULT_CYCLE    = 180                       -- 默认 180 秒（与 Air8780 一致）
local MIN_CYCLE        = 5                         -- 最小周期
local MAX_CYCLE        = 86400                     -- 最大周期（1 天）
local HEARTBEAT_SEC    = 60                        -- 心跳间隔（秒）
                                                 -- 不要用 excloud 默认的 300 秒：平台在线判定
                                                 -- 窗口通常 60~180 秒，300 秒会导致大部分时间
                                                 -- 被判离线（连接其实在，数据也在发）。


local WIFI_RSSI_FIELD  = 1295                      -- 自定义字段：WiFi 信号（官方表无此项）

-- ==================== 模块状态 ====================

local report_cycle      = DEFAULT_CYCLE
local report_enabled    = true
local report_timer      = nil
local boot_count        = 0
local last_report_time  = 0
local last_report_ok    = false
local last_report_err   = ""
local last_field_count  = 0
local fskv_ready        = false
local report_busy       = false

-- 其他模块推过来的缓存数据
local battery_cache     = nil    -- { present, level, voltage, charging, usb }

-- ==================== 小工具 ====================

--- 安全调用：函数存在才调用，异常不影响调用方
local function safe_call(name, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then
        log.debug("aircloud", "probe " .. name .. " failed:", r1)
        return nil, nil
    end
    return r1, r2
end

--- 探测某个 API 是否可用（不实际调用）
--- 能力探测：某个库对象上是否有可用的函数
--- 【坑】绝不能用 type(t) == "table" 做前置判断。
---   LuatOS 的 C 库可能是 userdata 实现（靠 __index 元方法暴露函数），
---   按 table 判会把整个库误判成「不存在」，导致所有采集字段静默丢失。
---   真机现象：上报只剩 4 个「不经过能力探测」的字段
---   （设备ID兜底 / 固件版本 / 时间戳 / 开机次数），其余全丢。
---   正确做法：容忍任意类型，用 pcall 兜住索引异常即可。
local function has_api(t, key)
    if t == nil then return false end
    local ok, f = pcall(function() return t[key] end)
    return ok and type(f) == "function"
end

--- 数值有效性判断（排除 nil / 非 number / NaN / ±inf）
local function valid_num(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--- 非空字符串判断
local function valid_str(v)
    return type(v) == "string" and #v > 0
end

--- 夹取
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ==================== fskv 读写 ====================

local function init_fskv()
    if fskv_ready then return true end
    if not fskv then return false end
    local ok = pcall(fskv.init)
    if not ok then return false end
    fskv_ready = true
    return true
end

local function fskv_read_number(key, default, min_val, max_val)
    if not init_fskv() then return default end
    local ok, val = pcall(fskv.get, key)
    if not ok or not valid_num(val) then return default end
    if min_val and max_val then val = clamp(val, min_val, max_val) end
    return val
end

local function fskv_write(key, val)
    if not init_fskv() then return false end
    local ok = pcall(fskv.set, key, val)
    return ok and true or false
end

-- ==================== 周期 / 开关读写 ====================

local function get_report_cycle()
    return fskv_read_number(FSKV_CYCLE_KEY, DEFAULT_CYCLE, MIN_CYCLE, MAX_CYCLE)
end

local function set_report_cycle(seconds)
    if not valid_num(seconds) then return false end
    seconds = math.floor(clamp(seconds, MIN_CYCLE, MAX_CYCLE))
    report_cycle = seconds
    fskv_write(FSKV_CYCLE_KEY, seconds)
    log.info("aircloud", "上报周期已改为", seconds, "秒")
    return true
end

local function get_report_enabled()
    if not init_fskv() then return true end
    local ok, val = pcall(fskv.get, FSKV_ENABLE_KEY)
    if not ok or val == nil then return true end
    return val and true or false
end

local function set_report_enabled(on)
    report_enabled = on and true or false
    fskv_write(FSKV_ENABLE_KEY, report_enabled)
    log.info("aircloud", "上报开关已设为", report_enabled and "开" or "关")
    sys.publish("AIRCLOUD_ENABLE_CHANGED", report_enabled)
    return true
end

-- ==================== 设备 ID（必须与 excloud 鉴权 ID 同源）============================
-- 【为什么不能自己随便挑一个】平台靠两处标识认设备，两者必须一致：
--   1) 鉴权/消息头里的 device_id（excloud 内部 config.device_id）→ 决定「连接归属谁」
--   2) 上报 TLV 798「设备号」→ 决定「这批数据归属谁」
--   两者不一致时的典型现象：web 端显示离线 + 数据查询查不到，
--   但平台的消息流水里又能看见原始 TLV（因为流水不校验归属）。
--
-- excloud.get_device_id_by_type()（excloud.lua:417）由 device_type 决定取值路径：
--   1 (Air780E/Air8000/Air700) → mobile.imei()
--   2 (Air8101)                → wlan.getMac(nil, true)
--   3 (Air1601/1602/1780)      → mcu.unique_id():toHex()   ← 本机走这条
--   9 (PC 模拟)               → virtual_phone_number + 3 位序列号
-- 这里必须严格复刻同一路径，不能改优先级，否则平台对不上号。
--
-- 【坑】mcu.unique_id() 返回 userdata，取十六进制**必须链式调用** `uid:toHex()`。
--   写成 `local f = uid.toHex` 取不到方法（userdata 索引行为差异），
--   整条 fallback 会静默失败、最后兜底成 "unknown" —— 这正是数据查不到的根因。

local device_id_cache = nil

--- 复刻 excloud.get_device_type()（excloud.lua:1864），用于选对取 ID 的路径
--- @return number|nil  1=4G 2=WiFi 3=MCU 9=PC 模拟；判不出来返回 nil
local function probe_device_type()
    local ok, bsp = pcall(function() return rtos and rtos.bsp and rtos.bsp() end)
    if ok and bsp == "PC" then return 9 end

    local ok2, model = pcall(function()
        return hmeta and hmeta.model and hmeta.model()
    end)
    if not ok2 or type(model) ~= "string" then return nil end

    if model:find("^Air780E") or model:find("^Air8000") or model:find("^Air700") then return 1 end
    if model:find("^Air8101") then return 2 end
    if model:find("^Air1601") or model:find("^Air1602") or model:find("^Air1780") then return 3 end
    return nil
end

--- mcu.unique_id():toHex() —— 严格链式调用，勿改成 uid.toHex
-- 【坑·真机踩过】unique_id() 返回的是**二进制串**（type 也是 string！），
--   若写 `if type(uid) == "string" then return uid end` 会把原始字节原样塞进 TLV，
--   平台日志里显示成乱码 "Ɠ"（即 C8C2C693F482 的前两字节 C6 93 当 UTF-8 打印），
--   而 excloud 消息头里的 dev 却是正确的十六进制（它内部无条件 string.toHex）。
--   两条路径必须一致 → 这里也**无条件转十六进制**，二进制串就地逐字节转。
local function read_uid_hex()
    if not has_api(mcu, "unique_id") then return nil end
    local ok, hex = pcall(function()
        local uid = mcu.unique_id()
        if uid == nil then return nil end
        if type(uid) == "string" then
            return (uid:gsub(".", function(c)
                return string.format("%02X", string.byte(c))
            end))
        end
        return uid:toHex()                      -- ← 关键：链式调用
    end)
    if ok and valid_str(hex) then return hex end
    return nil
end

--- wlan.getMac(nil, true) —— WiFi MAC 字符串
local function read_wifi_mac()
    if not has_api(wlan, "getMac") then return nil end
    local ok, a, b = pcall(wlan.getMac, nil, true)
    if not ok then return nil end
    if valid_str(a) then return a end
    if valid_str(b) then return b end
    return nil
end

local function get_device_id()
    if device_id_cache then return device_id_cache end

    -- ---- 主路径：严格按 excloud 的 device_type 取，保证与鉴权 ID 完全一致 ----
    local dtype = probe_device_type()
    if dtype == 3 then
        local v = read_uid_hex()                -- MCU 主控（本机 Air1601/8601）
        if v then device_id_cache = v; return v end
    elseif dtype == 2 then
        local v = read_wifi_mac()               -- WiFi 主控
        if v then device_id_cache = v; return v end
    elseif dtype == 1 then                      -- 4G 主控
        if mobile_usable() and has_api(mobile, "imei") then
            local v = safe_call("mobile.imei", mobile.imei)
            note_mobile(valid_str(v))
            if valid_str(v) then device_id_cache = v; return v end
        end
    end
    -- dtype == 9（PC 模拟）：excloud 用 virtual_phone_number 拼 ID，
    -- 那是 excloud 内部 config，这里拿不到，直接走兜底（仅影响模拟器显示）。

    -- ---- 兜底：device_type 判不出来或对应 API 缺失时，逐个试探 ----
    local v = read_uid_hex();          if v then device_id_cache = v; return v end
    v = read_wifi_mac();               if v then device_id_cache = v; return v end
    if mobile_usable() and has_api(mobile, "imei") then
        local imei = safe_call("mobile.imei", mobile.imei)
        note_mobile(valid_str(imei))
        if valid_str(imei) and imei ~= "pc_simulator" then
            device_id_cache = imei; return imei
        end
    end
    if has_api(hmeta, "devid") then
        local dv = safe_call("hmeta.devid", hmeta.devid)
        if valid_str(dv) then device_id_cache = dv; return dv end
    end

    -- 最后兜底：宁可上报 "unknown" 也不能崩，但平台会因此无法归属数据
    device_id_cache = "unknown"
    log.warn("aircloud", "设备 ID 全部取值失败，上报数据将无法被平台归属")
    return device_id_cache
end

-- ==================== mobile.* RPC 熔断器 ====================
-- 【背景·真机踩过】Air1601 的 mobile.* 全部是 airlink RPC（luat_mobile_airlink_rpc.c
--   → drv_rpc_mobile，rpc_id=0x0700，FAST 档超时仅 120ms），由外挂模组应答。
--   Air8601 外挂模组是「Air6205 WiFi / Air780ER2 4G」二选一：**WiFi 版没有蜂窝服务**，
--   RPC 无人应答 → 每个调用干等 120ms 后返回 nil，真机日志：
--     E/airlink.rpc rpc yield timeout after 120ms (pkgid=0x3)   ← mobile.csq
--     E/airlink.rpc rpc yield timeout after 120ms (pkgid=0x4)   ← mobile.status
--     E/airlink.rpc rpc yield timeout after 170ms (pkgid=0x5)   ← mobile.iccid
--     E/airlink.rpc rpc: timeout after 123ms (pkgid=0x6 rpc_id=0x0700) ← mobile.imei
--   一轮上报白等 ~500ms 还刷 4 条 E 级日志。故连续失败 3 次后静默一段时间再重试
--   （外挂 4G 时 RPC 正常应答，不会触发熔断；开机初期偶发失败也会在冷却后自动恢复）。
local mobile_ok_seen     = false   -- 本开机周期内 mobile.* 有过一次成功响应
local mobile_fail_streak = 0      -- 连续失败计数
local mobile_mute_until  = 0      -- 静默截止时间（os.time 秒）
local MOBILE_FAIL_LIMIT  = 3
local MOBILE_MUTE_SEC    = 600    -- 静默 10 分钟后再试

local function mobile_usable()
    return os.time() >= mobile_mute_until
end

--- 记录一次 mobile.* 调用结果（true=拿到了有效返回值）
local function note_mobile(ok)
    if ok then
        mobile_ok_seen = true
        mobile_fail_streak = 0
        return
    end
    mobile_fail_streak = mobile_fail_streak + 1
    if mobile_fail_streak >= MOBILE_FAIL_LIMIT then
        mobile_fail_streak = 0
        mobile_mute_until = os.time() + MOBILE_MUTE_SEC
        log.warn("aircloud", "mobile.* 连续", MOBILE_FAIL_LIMIT,
                 "次无响应（外挂模组无蜂窝服务？如 Air6205 WiFi 版），",
                 "跳过蜂窝/基站字段", MOBILE_MUTE_SEC, "秒后重试")
    end
end

-- ==================== 采集器 ====================

--- 信号强度：4G CSQ（0~31，99 表示未知）
local function collect_csq()
    if not mobile_usable() then return nil end
    if not has_api(mobile, "csq") then return nil end
    local v = safe_call("mobile.csq", mobile.csq)
    note_mobile(valid_num(v))
    if not valid_num(v) then return nil end
    if v <= 0 or v >= 99 then return nil end
    return math.floor(v)
end

-- CPU 温度采集：【已下线 · 2026-09-22】Air1601/8601 已核实不支持 CH_CPU（虚拟通道
-- 未实现，仅物理 ADC1/2/5/6；adc.get 恒返回 -1 = 读取失败码，曾产生 -0.001℃ 假温度）。
-- 产品决策只报基本信息，ENV_TEMPERATURE(263) 不再上报。

--- 电池：优先用 battery_app 推送的缓存（它自己 10 秒轮询一次，白嫖）
-- 注意：battery_app 的 voltage 单位是 mV（如 3900），上报前转 V
local function collect_battery()
    if not battery_cache then return nil, nil end
    local level = battery_cache.level
    local volt  = battery_cache.voltage
    if not valid_num(level) or level < 0 then level = nil end
    if not valid_num(volt) or volt <= 0 then
        volt = nil
    else
        volt = volt / 1000          -- mV → V
        if volt < 0.5 or volt > 6 then volt = nil end
    end
    -- battery_app 明确判定"无电池"时不上报
    if battery_cache.present == false then return nil, nil end
    return level, volt
end

-- LBS 基站定位：【已下线 · 2026-09-22】Air1601/8601 WiFi 版无蜂窝，基站定位无从谈起，
-- GNSS 经纬度(512/513) 不再上报。若未来换 4G 外挂且确需定位，从 git 历史找回
-- collect_lbs()/get_lbsloc2()，并注意 lbsLoc2 顶层 require 陷阱（头部第 7 条）。

--- 网络类型：1=WiFi 2=蜂窝 3=以太网
local function collect_net_type()
    -- WiFi 已连接（rssi 有效）
    if has_api(wlan, "getInfo") then
        local info = safe_call("wlan.getInfo", wlan.getInfo)
        if type(info) == "table" and valid_num(info.rssi) and info.rssi ~= 0 then
            return 1
        end
    end
    -- 蜂窝注册成功
    if mobile_usable() and has_api(mobile, "status") then
        local st = safe_call("mobile.status", mobile.status)
        note_mobile(valid_num(st))          -- RPC 有应答即算成功
        if valid_num(st) and st > 0 then return 2 end
    end
    -- 按默认网卡名兜底
    if has_api(socket, "adapter") then
        local ad = safe_call("socket.adapter", socket.adapter)
        if valid_str(ad) then
            if ad:find("eth") then return 3 end
            if ad:find("wlan") or ad:find("wifi") then return 1 end
            if ad:find("4g") or ad:find("cellular") or ad:find("ppp") then return 2 end
        end
    end
    return nil
end

--- WiFi RSSI —— 上报值 = rssi + 100（偏移正值，规避 uint32 线格式不支持负数）
-- 真值 -45dBm → 上报 55；0 表示 ≤ -100dBm 或未知（不报）。
-- 【为什么偏移】excloud 的 INTEGER 编码是 uint32 大端，-55 会被编码成补码乱数据，
--   所以自定义字段 1295 的语义定为「rssi + 100」，平台侧展示时减 100 还原。
local function collect_wifi_rssi()
    if not has_api(wlan, "getInfo") then return nil end
    local info = safe_call("wlan.getInfo", wlan.getInfo)
    if type(info) ~= "table" then return nil end
    local rssi = info.rssi
    if not valid_num(rssi) or rssi == 0 then return nil end
    if rssi > 0 then rssi = -rssi end         -- 有些固件返回正值
    local shifted = math.floor(rssi) + 100
    if shifted <= 0 then return nil end       -- 太弱/无效，不报
    return shifted
end

--- SIM ICCID
local function collect_iccid()
    if not mobile_usable() then return nil end
    if not has_api(mobile, "iccid") then return nil end
    local v = safe_call("mobile.iccid", mobile.iccid)
    note_mobile(valid_str(v))
    if valid_str(v) and v ~= "pc_simulator" then return v end
    return nil
end

--- 开机原因
local function collect_boot_reason()
    if not has_api(rtos, "rebootReason") then return nil end
    local v = safe_call("rtos.rebootReason", rtos.rebootReason)
    if valid_num(v) then return math.floor(v) % 100000 end
    return nil
end

--- 内存占用（当前已用，字节）
--- 【坑】rtos.meminfo(domain) 返回的是**多个数值** (total, used[, max_used])，不是 table：
---   local total, used = rtos.meminfo("sys")            -- exapp.lua:4152
---   local t, used, max = rtos.meminfo("sys")           -- exremotefile.lua:1253
--- 按 table 取 .used 会恒为 nil，导致该字段一直静默丢失。
local function collect_mem()
    if not has_api(rtos, "meminfo") then return nil end

    -- 依次试 lua 域 / 无参（默认域）/ sys 域，任一拿到 used 即可
    local ok, total, used = pcall(rtos.meminfo, "lua")
    if ok and valid_num(used) and used > 0 then return math.floor(used) end

    ok, total, used = pcall(rtos.meminfo)
    if ok and valid_num(used) and used > 0 then return math.floor(used) end

    ok, total, used = pcall(rtos.meminfo, "sys")
    if ok and valid_num(used) and used > 0 then return math.floor(used) end

    return nil
end

-- ==================== TLV 组装 ====================

--- 向 tlv_list 追加一项，值无效则静默跳过
-- 这是本模块最关键的防御：build_tlv 遇到 nil/非 number 会返回 false，
-- 进而让 excloud.send 整体失败，所以必须逐项判空。
--
-- 【坑·真机踩过】excloud 的 INTEGER / FLOAT 全部按 **uint32 大端**编码
--   （INTEGER = floor(v)；FLOAT = floor(v*1000)），to_big_endian 对负数只打一条
--   "数值溢出" 告警然后照样编码 → 平台收到的是补码乱数据（-1 变 4294967295）。
--   所以负数在线格式上**根本不可表示**，这里统一拒绝并告警，宁缺毋滥。
--   需要负值语义的字段（如 WiFi RSSI）在采集器里就地换成偏移正值。
local function push_tlv(list, field, data_type, value)
    if value == nil then return false end
    if type(value) == "number" then
        if not valid_num(value) then return false end
        -- 线格式可表示性：uint32 范围内、且按该类型缩放后仍非负
        local scaled = value
        if data_type == excloud.DATA_TYPES.FLOAT then
            scaled = value * 1000          -- FLOAT 实际编码值
        end
        if scaled < 0 or scaled >= 4294967296 then
            log.warn("aircloud", "字段", field, "值", value, "超出线格式(uint32)可表示范围，已丢弃")
            return false
        end
    elseif type(value) == "string" then
        if #value == 0 then return false end
    elseif type(value) ~= "boolean" then
        return false
    end
    list[#list + 1] = { field_meaning = field, data_type = data_type, value = value }
    return true
end

--- 采集所有可用字段，组装 TLV 列表
--- @return table tlv_list, table collected_names
local function build_report_tlvs()
    local DT = excloud.DATA_TYPES
    local FM = excloud.FIELD_MEANINGS
    local list = {}
    local names = {}

    local function add(name, field, dtype, value)
        if push_tlv(list, field, dtype, value) then
            names[#names + 1] = name
        end
    end

    -- ---- 设备身份 ----
    -- 798 是平台的「设备号」语义字段（决定数据归属），必须与鉴权 device_id 一致；
    -- 1293 是自定义字段，照 8780 的做法冗余再存一份，避免平台对 798 有额外语义处理时查不到。
    add("设备ID",   FM.DEVICE_ID,        DT.ASCII, get_device_id())
    add("设备ID2",  1293,                DT.ASCII, get_device_id())
    add("固件版本", FM.FIRMWARE_VERSION, DT.ASCII, _G.VERSION)

    -- ---- 网络 ----
    add("信号强度", FM.SIGNAL_STRENGTH_4G, DT.INTEGER, collect_csq())
    add("网络类型", FM.NETWORK_TYPE,       DT.INTEGER, collect_net_type())
    add("SIM卡",    FM.SIM_ICCID,          DT.ASCII,   collect_iccid())

    -- ---- 环境 / 定位 ----
    -- 【已下线 · 2026-09-22】CPU 温度(263) 与经纬度(512/513) 不再上报：
    -- Air1601/8601 已核实不支持 CH_CPU 与基站定位（见头部第 10 条），只报基本信息。

    -- ---- 电源 ----
    local level, volt = collect_battery()
    add("电池电量", FM.BATTERY_LEVEL, DT.INTEGER, level)
    add("电池电压", FM.VOLTAGE,       DT.FLOAT,   volt)

    -- ---- 运行状态 ----
    add("时间戳",   FM.TIMESTAMP,            DT.INTEGER, os.time())
    add("开机原因", FM.BOOT_REASON,          DT.INTEGER, collect_boot_reason())
    add("开机次数", FM.BOOT_COUNT,           DT.INTEGER, boot_count)
    add("内存占用", FM.LUA_MEM_CURRENT_USED, DT.INTEGER, collect_mem())

    -- ---- WiFi RSSI（自定义字段，官方表无 WiFi 信号项）----
    add("WiFi-RSSI", WIFI_RSSI_FIELD, DT.INTEGER, collect_wifi_rssi())

    return list, names
end

-- ==================== 上报执行 ====================

local function publish_result(success, count, err)
    sys.publish("AIRCLOUD_REPORT_RESULT", {
        success = success, time = os.time(), count = count or 0, err = err or "",
    })
end

local function do_report(reason)
    if report_busy then
        log.warn("aircloud", "上一轮上报尚未结束，跳过本次")
        return false
    end
    report_busy = true

    local st = has_api(excloud, "status") and excloud.status() or nil
    if not st or not st.is_open or not st.is_connected then
        report_busy = false
        last_report_ok, last_report_err, last_report_time = false, "未连接", os.time()
        publish_result(false, 0, "未连接")
        return false
    end

    local ok_build, tlv_list, names = pcall(build_report_tlvs)
    if not ok_build or type(tlv_list) ~= "table" or #tlv_list == 0 then
        report_busy = false
        last_report_ok, last_report_err = false, "无可用字段"
        log.warn("aircloud", "本轮无可上报字段")
        publish_result(false, 0, "无可用字段")
        return false
    end

    local ok, ret, err = pcall(excloud.send, tlv_list, false)
    report_busy = false

    if ok and ret ~= false then
        last_report_ok   = true
        last_report_err  = ""
        last_report_time = os.time()
        last_field_count = #tlv_list
        log.info("aircloud", "上报成功", "字段数", #tlv_list, "原因", reason or "-",
                 "字段:", table.concat(names, ","))
        publish_result(true, #tlv_list, "")
        return true
    end

    last_report_ok   = false
    last_report_err  = tostring(err or "发送失败")
    last_report_time = os.time()
    last_field_count = #tlv_list
    log.warn("aircloud", "上报失败:", last_report_err)
    publish_result(false, #tlv_list, last_report_err)
    return false
end

-- ==================== 上报定时器 ====================

local function start_report_timer()
    if report_timer then
        sys.timerStop(report_timer)
        report_timer = nil
    end
    if not report_enabled then
        log.info("aircloud", "上报已关闭，定时器不启动")
        return
    end
    report_timer = sys.timerLoopStart(function()
        -- 定时器回调里不能长时间阻塞，把重活丢给上报协程
        sys.publish("AIRCLOUD_REPORT_TICK", "timer")
    end, report_cycle * 1000)
    log.info("aircloud", "上报定时器已启动，周期", report_cycle, "秒")
end

-- ==================== 下行命令处理 ====================

--- 回复云端（走 CONTROL_RESPONSE）
local function send_control_response(msg)
    local DT = excloud.DATA_TYPES
    local FM = excloud.FIELD_MEANINGS
    pcall(excloud.send, {
        { field_meaning = FM.CONTROL_RESPONSE, data_type = DT.ASCII, value = tostring(msg) }
    }, false)
end

--- TTS 播报派发：长度/能力检查 + 转发 tts_app + 回执
local function dispatch_tts(tts_text)
    local tts_app = require "tts_app"
    if #tts_text > 300 then
        send_control_response("ERR tts too long, max 300 bytes")
    elseif not tts_app.available() then
        send_control_response("ERR no audio")
    else
        tts_app.say(tts_text)
        send_control_response("OK tts len=" .. #tts_text)
    end
end

local function handle_control_command(cmd)
    if not valid_str(cmd) then return end
    log.info("aircloud", "收到下行命令:", cmd)

    -- cycle:180 —— 改上报周期
    local cycle_val = cmd:match("^cycle[:=](%d+)$")
    if cycle_val then
        local seconds = tonumber(cycle_val)
        if seconds and seconds >= MIN_CYCLE then
            set_report_cycle(seconds)
            start_report_timer()
            send_control_response("OK cycle=" .. report_cycle)
        else
            send_control_response("ERR cycle too small, min=" .. MIN_CYCLE)
        end
        return
    end

    -- backlight:60 —— 调屏幕背光（10~100）
    local bl_val = cmd:match("^backlight[:=](%d+)$")
    if bl_val then
        local level = tonumber(bl_val)
        if level then
            level = math.floor(clamp(level, 10, 100))
            sys.publish("DISPLAY_BRIGHTNESS_SET", level)
            send_control_response("OK backlight=" .. level)
        else
            send_control_response("ERR backlight invalid")
        end
        return
    end

    -- led:on / led:off / led:blink —— LED 控制（web 端「控制」页按钮发的就是这个）
    -- 本机（Air1601/8601）暂无 LED 硬件映射（引脚未定义，不瞎编），先做协议层闭环：
    -- 记录 + 广播 LED_CONTROL 事件（将来 LED 应用订阅该事件即可落地硬件动作），并回复 web。
    local led_val = cmd:match("^led[:=](%a+)$")
    if led_val then
        if led_val == "on" or led_val == "off" or led_val == "blink" then
            sys.publish("LED_CONTROL", led_val)
            send_control_response("OK led=" .. led_val)
        else
            send_control_response("ERR led mode invalid, use on/off/blink")
        end
        return
    end

    -- ttshex:<hex> —— TTS 文本的十六进制编码（UTF-8 字节逐两位 hex）
    -- 【坑·真机踩过 2026-09-23】纯中文走 tts: 直发会被云端 ASCII 通道消毒成 '?'：
    --   web 发 "tts:你好"(UTF-8 共 10 字节) 实际到达只剩 "tts:??"(6 字节)，
    --   消息长度 10 = TLV 头 4 + 值 6 可验证。纯十六进制是可打印 ASCII，
    --   100% 无损透传，设备端解码回 UTF-8 文本再播。web 端 TTS 走这条。
    local tts_hex = cmd:match("^ttshex[:=]([0-9a-fA-F]+)$")
    if tts_hex then
        local ok_dec, tts_text = pcall(string.gsub, tts_hex, "%x%x",
            function(h) return string.char(tonumber(h, 16)) end)
        if ok_dec and type(tts_text) == "string" and #tts_text > 0 then
            log.info("aircloud", "TTS(hex) 解码:", tts_text)
            dispatch_tts(tts_text)
        else
            send_control_response("ERR tts hex decode failed")
        end
        return
    end

    -- tts:<文本> —— 云端下发 TTS 语音播报（ASCII 文本直发；含中文请走 ttshex:）
    -- 无音频能力（hw.audio 未配置）明确回 ERR no audio，让 web 能区分「没播」的原因
    local tts_text = cmd:match("^tts[:=](.+)$")
    if tts_text then
        dispatch_tts(tts_text)
        return
    end

    -- ttsstop —— 停止当前 TTS 播报（独立命令，不用 tts:stop 避免与播报文本歧义）
    if cmd == "ttsstop" then
        local tts_app = require "tts_app"
        tts_app.stop()
        send_control_response("OK tts stopped")
        return
    end

    -- report:once —— 立即上报一次
    if cmd == "report:once" or cmd == "report" then
        sys.publish("AIRCLOUD_REPORT_TICK", "cloud_cmd")
        send_control_response("OK report triggered")
        return
    end

    -- report:on / report:off —— 开关上报
    local onoff = cmd:match("^report[:=](%a+)$")
    if onoff then
        if onoff == "on" then
            set_report_enabled(true)
            start_report_timer()
            send_control_response("OK report=on")
        elseif onoff == "off" then
            set_report_enabled(false)
            start_report_timer()
            send_control_response("OK report=off")
        else
            send_control_response("ERR unknown report flag")
        end
        return
    end

    -- status —— 查状态
    if cmd == "status" then
        local st = has_api(excloud, "status") and excloud.status() or {}
        send_control_response(string.format(
            "OK cycle=%d enable=%s last=%s fields=%d conn=%s auth=%s",
            report_cycle, report_enabled and "on" or "off",
            last_report_ok and "ok" or (last_report_err ~= "" and last_report_err or "none"),
            last_field_count,
            tostring(st.is_connected), tostring(st.is_authenticated)))
        return
    end

    send_control_response("ERR unknown cmd: " .. cmd)
end

-- ==================== 上报主协程 ====================

local function report_task_func()
    -- 1) 等网络就绪
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    -- 2) 读配置
    report_cycle   = get_report_cycle()
    report_enabled = get_report_enabled()
    boot_count     = fskv_read_number(FSKV_BOOTCNT_KEY, 0, 0, 1e9) + 1
    fskv_write(FSKV_BOOTCNT_KEY, boot_count)

    log.info("aircloud", "启动", "周期", report_cycle, "秒",
             "开关", report_enabled and "on" or "off", "开机次数", boot_count)

    -- 3) 初始化 excloud
    --    注意：不传 device_type（新版 setup 会忽略并自动识别）
    --    virtual_phone_number 仅 PC 模拟器需要
    excloud.setup({
        use_getip            = true,
        auth_key             = _G.PROJECT_KEY,
        transport            = "tcp",
        auto_reconnect       = true,
        reconnect_interval   = 10,
        max_reconnect        = 5,
        virtual_phone_number = "10012345678",
    })

    excloud.open()

    -- 【坑·真机踩过】start_heartbeat 的 custom_data 绝不能为空！
    --   不传时 excloud 内部 heartbeat_data = custom_data or {} → 空表，
    --   excloud.send 对空 TLV 直接拒绝："没有有效的TLV数据可发送"，
    --   心跳周期性失败 → 平台判定设备离线（连接其实在，数据偶尔也能发）。
    --   所以这里必须给一份**非空**载荷；用静态身份字段即可（心跳只求保活+归属）。
    excloud.start_heartbeat(HEARTBEAT_SEC, {
        { field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID,        data_type = excloud.DATA_TYPES.ASCII, value = get_device_id() },
        { field_meaning = excloud.FIELD_MEANINGS.FIRMWARE_VERSION, data_type = excloud.DATA_TYPES.ASCII, value = _G.VERSION or APP_VERSION },
    })   -- 显式 60 秒，勿用默认 300 秒（会判离线）

    -- 4) 启动定时上报
    start_report_timer()

    -- 5) 首次上报稍等一下，让鉴权走完
    sys.wait(5000)
    sys.publish("AIRCLOUD_REPORT_TICK", "boot")

    -- 6) 事件循环：响应定时 tick（重活放协程里，避免阻塞定时器）
    while true do
        local _, reason = sys.waitUntil("AIRCLOUD_REPORT_TICK")
        if report_enabled then
            do_report(reason)
        end
    end
end

sys.taskInit(report_task_func)

-- ==================== 事件订阅 ====================

-- excloud 连接事件
excloud.on(function(event, data)
    if event == "connect_result" then
        log.info("aircloud", "连接结果:", data and data.success, data and data.message or "")
    elseif event == "auth_result" then
        log.info("aircloud", "鉴权结果:", data and data.success, data and data.message or "")
        if data and data.success then
            sys.publish("AIRCLOUD_AUTH_OK")
            -- 鉴权成功后补一次上报，让云端尽快看到设备
            sys.publish("AIRCLOUD_REPORT_TICK", "auth")
        end
    elseif event == "message" then
        -- data 为解析后的 TLV 列表，也可能是单条
        local FM = excloud.FIELD_MEANINGS
        local DT = excloud.DATA_TYPES
        local function handle_item(item)
            if type(item) ~= "table" then return end
            if item.field ~= FM.CONTROL_COMMAND then return end
            if valid_str(item.value) then
                handle_control_command(item.value)
            elseif item.value ~= nil then
                handle_control_command(tostring(item.value))
            end
        end
        if type(data) == "table" then
            if data.field then
                handle_item(data)                -- 单条 TLV
            else
                -- 【坑·真机踩过】excloud 的 "message" 事件载荷是 parse_message() 的返回值
                --   { header = {...}, tlvs = { {field,type,length,raw_value,value}, ... } }，
                --   **不是** TLV 数组！直接 ipairs(data) 只会遍历到空的数组部分，
                --   下行命令全部哑火（真机日志只有"解析消息头"、没有"收到下行命令"，
                --   web 发 led:on/led:off 设备毫无反应）。必须取 data.tlvs。
                local items = data.tlvs or data   -- 兼容裸数组形态（旧桩/直调）
                for _, item in ipairs(items) do
                    handle_item(item)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("aircloud", "连接断开:", data and data.message or "")
    elseif event == "reconnect_failed" then
        log.error("aircloud", "重连失败:", data and data.message or "")
    elseif event == "send_result" then
        if data and data.success == false then
            log.warn("aircloud", "发送失败:", data.message or "")
        end
    elseif event == "auth_key_error" then
        log.error("aircloud", "auth_key 无效，请在 main.lua 检查 PROJECT_KEY")
    end
end)

-- 设置页：改周期
sys.subscribe("AIRCLOUD_SET_CYCLE", function(seconds)
    if set_report_cycle(seconds) then
        start_report_timer()
    end
end)

-- 设置页：开关上报
sys.subscribe("AIRCLOUD_SET_ENABLE", function(on)
    set_report_enabled(on)
    start_report_timer()
    if report_enabled then
        sys.publish("AIRCLOUD_REPORT_TICK", "manual_enable")
    end
end)

-- 设置页：立即上报一次
sys.subscribe("AIRCLOUD_REPORT_NOW", function()
    sys.publish("AIRCLOUD_REPORT_TICK", "manual")
end)

-- 设置页：查状态
sys.subscribe("AIRCLOUD_GET_STATUS", function()
    local st = (has_api(excloud, "status") and excloud.status()) or {}
    sys.publish("AIRCLOUD_STATUS_RESP", {
        cycle         = report_cycle,
        enabled       = report_enabled,
        connected     = st.is_connected and true or false,
        authenticated = st.is_authenticated and true or false,
        is_open       = st.is_open and true or false,
        last_ok       = last_report_ok,
        last_time     = last_report_time,
        last_err      = last_report_err,
        last_count    = last_field_count,
        boot_count    = boot_count,
        device_id     = get_device_id(),
        version       = APP_VERSION,
    })
end)

-- 白嫖 battery_app 的电池状态（它自己 10 秒轮询）
sys.subscribe("BATTERY_STATUS", function(data)
    if type(data) == "table" then
        battery_cache = data
    end
end)

log.info("aircloud", "模块已加载 v" .. APP_VERSION)
