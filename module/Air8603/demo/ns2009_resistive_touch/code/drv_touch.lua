--[[
@module  drv_touch
@summary 触摸驱动：核心库 tp（NS2009，新版 API，含标定系数 fskv 持久化）
@version 1.3
@date    2026.11.10
@usage
API 用法（新版 tp API）：
  tp.init("ns2009", {port=, pin_int=, w=, h=}, callback)
    新版参数表只有 port/pin_int/w/h（旧版 address/swap_xy 已移除，地址/方向
    改由固件内部处理）。callback(tp_device, points)：points[1] = {event, x, y, ...}
    event 取值：tp.EVENT_DOWN / tp.EVENT_MOVE / tp.EVENT_UP
  tp.calibration(dev, callback)
    callback(event, a, b)：event=="point" 时 a,b 是本次要点击的十字的屏幕坐标；
    完成事件时 a 携带标定结果。四点顺序：左上、右上、左下、右下。
  tp.calibration(dev)
    读回当前生效的标定 table 副本；未标定返回 nil,"not_calibrated"。
    可在 callback("done", true) 里直接读；重新标定过程中只会读到上一次
    已生效的结果（不要在 point 回调里读）。
  tp.calibration(dev, data)
    同步校验并应用 table（fskv 存档回灌）：成功返回 true，下一次触摸生效；
    按压中/标定未结束返回 false,"busy"；数据不合法返回 false,"invalid_data"。

tp 库内部完成 I2C 读取、按下判定、坐标映射与标定，本模块负责：
  1. init：i2c.setup + tp.init，把事件同步进 TP_STATE（官方 demo 同款日志节奏）
  2. calibrate：包一层 tp.calibration，兼容阻塞/异步两种固件实现；
     完成后自动读回系数并存 fskv（新版 API 支持读回/回灌，存档真正有效）
  3. restore_calibration：上电从 fskv 取存档回灌，成功则跳过四点标定
  4. sample：把 TP_STATE 快照成 poll 风格的表，界面逻辑与驱动来源解耦

★ 标定存档（新版 tp API 起可用）：系数以 json 字符串存 fskv
  （键名 config.touch.cal_kv，默认 ns2009_cal；总开关 config.touch.save_cal）。
  注意：系数与触摸硬件绑定，换屏/换排线/结构位移后旧系数"合法但可能不准"，
  此时点"标定"按钮重标即可，完成后自动覆盖存档。
]]

local M = {}

local TP_STATE = { event = 0, x = 0, y = 0, pressed = false, seq = 0, moves = 0 }
local M_DEV = nil        -- tp.init 返回的设备句柄
local M_CFG = nil        -- config.touch 配置（cal_kv 键名等）

--[[tp.init 的事件回调：官方 demo 同款日志节奏（DOWN/UP 必打，MOVE 每 5 个一条）]]
local function tp_callback(_, points)
    local p = points and points[1]
    if not p then return end

    if p.event == tp.EVENT_DOWN then
        TP_STATE.pressed = true
    elseif p.event == tp.EVENT_UP then
        TP_STATE.pressed = false
    end
    -- MOVE 只在按下状态时更新坐标（UP 后的残留 MOVE 不采）
    if p.event ~= tp.EVENT_MOVE or TP_STATE.pressed then
        TP_STATE.x, TP_STATE.y = p.x, p.y
    end
    TP_STATE.event = p.event
    TP_STATE.seq = TP_STATE.seq + 1

    local names = { [tp.EVENT_DOWN] = "DOWN", [tp.EVENT_MOVE] = "MOVE", [tp.EVENT_UP] = "UP" }
    if p.event == tp.EVENT_MOVE then
        TP_STATE.moves = (TP_STATE.moves + 1) % 5
        if TP_STATE.moves ~= 0 then return end
    else
        TP_STATE.moves = 0
    end
    log.info("touch", names[p.event] or p.event, p.x, p.y)
end

--[[
初始化触摸：i2c.setup + tp.init（整个固件只能 tp.init 一次）
@param table cfg config.lua 的 CFG.touch
@return userdata dev 成功时返回设备句柄
@return string  err  失败原因
]]
function M.init(cfg)
    if not tp then
        return nil, "固件未启用 tp"
    end
    if cfg.pin_int == nil then
        return nil, "请填写 touch.pin_int（PENIRQ 对应的 GPIO 编号）"
    end
    if i2c.setup(cfg.i2c_id, i2c.SLOW) ~= 1 then
        return nil, "I2C 初始化失败 id=" .. tostring(cfg.i2c_id)
    end

    -- refresh_rate：触摸读取刷新率（tp.md 可选参数，"部分触摸芯片可配置此参数
    --   调整扫描频率"）。不设时固件用默认值，实测 ns2009 按住拖动坐标更新极稀疏：
    --   慢速滑动几乎收不到 MOVE（轨迹无线），快速滑动只有间断的线。
    --   显式调高扫描频率让 MOVE 事件连续上报。驱动不支持时该参数应被忽略。
    -- direction/swap_xy：触摸坐标方向（tp.md 可选参数），config.touch 可配，默认不设。
    --   NS2009 未标定映射的默认原点在左下角（Y 向上），与屏幕逻辑坐标（左上原点）
    --   上下颠倒——保持固件默认基准不翻转，靠首次上电强制四点标定解决方向问题。
    --   驱动不支持时该参数应被忽略（行为同不传）。
    local param = {
        port         = cfg.i2c_id,
        pin_int      = cfg.pin_int,
        w            = cfg.w,
        h            = cfg.h,
        refresh_rate = cfg.refresh_rate or 20,
    }
    if cfg.direction then param.direction = cfg.direction end
    -- if cfg.swap_xy   then param.swap_xy   = cfg.swap_xy   end
    local dev, err = tp.init("ns2009", param, tp_callback)
    if not dev then
        return nil, err or "tp.init 失败，请检查前面的驱动日志"
    end
    M_DEV = dev
    M_CFG = cfg
    log.info("touch", "NS2009 就绪（新版 tp API）",
        cfg.w .. "x" .. cfg.h, "int=PIN" .. tostring(cfg.pin_int),
        "refresh_rate=" .. tostring(cfg.refresh_rate or 20),
        "direction=" .. tostring(cfg.direction or "auto"),
        "swap_xy=" .. tostring(cfg.swap_xy or "none"))
    return dev
end

--[[设备句柄（未初始化时为 nil）]]
function M.get()
    return M_DEV
end

--[[
四点标定：包一层 tp.calibration（参考官方 demo 用法）
  回调风格：event=="point" 时 a,b = 本次要点击的十字的屏幕坐标；
            完成事件时 a = 标定结果。
  内部会等标定完成再返回（兼容阻塞/异步两种固件实现）：
    阻塞式：tp.calibration 返回时回调已跑完，等待循环立即退出；
    异步式：返回后回调稍后触发，这里等它（默认 60s 超时兜底）。
  标定期间触摸由核心库接管，界面主循环应自行挂起（见 ui_test）。
@param function draw 每个点回调 draw("point", a, b)，UI 用它画十字；可 nil
@param number timeout_ms 异步实现的完成等待超时，默认 60000
@param boolean auto_save true=完成后自动读回系数并存 fskv（开机自动路径）；
                false/nil=不自动存（手动路径由 UI 出"绿=保存/红=不保存"选择页）
@return boolean ok  true=标定流程完成；false=未启动
@return any     reason  ok=false 时为失败原因；ok=true 时为标定结果（DONE 的 a）
]]
function M.calibrate(draw, timeout_ms, auto_save)
    if not (tp and tp.calibration and M_DEV) then
        return false, "无 tp/tp.calibration 或设备未初始化"
    end

    local done, done_ev = nil, nil
    local ok, reason = tp.calibration(M_DEV, function(event, a, b)
        if event == "point" then
            log.info("touch", "POINT", a, b)
            if draw then draw("point", a, b) end
        else
            -- 到这里标定就结束了；★ 结束≠成功：固件超时/取消也走这里，
            -- 结果可能在 a 里（false/0=失败），所以事件名和结果都要记下来
            log.info("touch", "DONE", a, event)
            done, done_ev = a, tostring(event)
            if draw then draw("done", a, b) end
        end
    end)
    if not ok then
        return false, reason
    end

    -- 兼容阻塞/异步两种固件实现，等 DONE
    local tmo, limit = 0, (timeout_ms or 60000)
    while done == nil and tmo < limit do
        sys.wait(50)
        tmo = tmo + 50
    end
    if done == nil then
        -- 等待超时（固件没有任何结束事件）：UI 据此停在标定页出 TIME OUT + RETURN
        return false, "timeout"
    end
    if done == false or done == 0 then
        -- 固件上报了结束事件但结果是失败（实测：固件侧超时也走这里，
        -- 之前把这种当成成功返回 → UI 错误地出了 SAVE/NO 选择页）
        log.warn("touch", "标定结束事件但结果为失败", tostring(done), done_ev)
        return false, "cal_fail"
    end
    -- 标定完成：按 auto_save 决定是否读回并存 fskv（新版 API；done 后读到的是新结果）
    if auto_save then
        M.save_calibration()
    end
    return true, done
end

-- ============ 标定系数读回/回灌 + fskv 持久化（新版 tp API） ============

local KV_KEY = "ns2009_cal"   -- 默认 fskv 键名，可被 config.touch.cal_kv 覆盖
local FSKV_READY = false      -- fskv.init() 每次上电只需成功一次（★ 读/写/删之前都必须已 init）

--[[确保 fskv 已初始化：官方约定 kv 数据库要 init 后才能用（读/写都是），
    漏了 init 的表现就是"写入成功、重启后读不到"（kv_get 返回 nil）]]
local function ensure_fskv()
    if not (fskv and fskv.init) then
        return false
    end
    if not FSKV_READY then
        local ok, err = pcall(fskv.init)
        if ok then
            log.info("touch", "fskv 已初始化")
            FSKV_READY = true
        else
            log.warn("touch", "fskv init 失败", tostring(err))
        end
    end
    return FSKV_READY
end

--[[kv 写接口双名兼容：kv_set（新）/ set（老）]]
local function kv_put(key, s)
    if fskv.kv_set then return fskv.kv_set(key, s) end
    return fskv.set(key, s)
end

--[[kv 读接口双名兼容：kv_get（新）/ get（老）]]
local function kv_read(key)
    if fskv.kv_get then return fskv.kv_get(key) end
    return fskv.get(key)
end

--[[kv 删接口双名兼容：kv_del（新）/ del（老）]]
local function kv_drop(key)
    if fskv.kv_del then return fskv.kv_del(key) end
    return fskv.del(key)
end

--[[读回当前生效的标定 table 副本（tp.calibration(dev) 单参用法）
@return table data 成功时为副本；未标定时 nil,"not_calibrated"]]
function M.read_calibration()
    if not (tp and tp.calibration and M_DEV) then
        return nil, "无 tp/tp.calibration 或设备未初始化"
    end
    return tp.calibration(M_DEV)
end

--[[应用标定 table（tp.calibration(dev, data) 回灌用法），busy 时有限重试
@param table data 存档读回的系数表
@param number timeout_ms busy 重试总时长，默认 3000
@return boolean true=已应用，下一次触摸生效]]
function M.apply_calibration(data, timeout_ms)
    if not (tp and tp.calibration and M_DEV) then
        return false, "无 tp/tp.calibration 或设备未初始化"
    end
    local tmo, limit = 0, (timeout_ms or 3000)
    while true do
        local ok, err = tp.calibration(M_DEV, data)
        if ok then
            log.info("touch", "标定系数已回灌")
            return true
        end
        -- busy = 按压中/标定未结束，等一会重试；其它错误直接失败
        if err ~= "busy" or tmo >= limit then
            return false, err
        end
        sys.wait(200)
        tmo = tmo + 200
    end
end

--[[标定系数存档到 fskv（json 字符串；键名 config.touch.cal_kv，默认 ns2009_cal）]]
function M.save_calibration()
    local data, err = M.read_calibration()
    if not data then
        log.warn("touch", "标定系数读回失败，不存档", tostring(err))
        return false, err
    end
    if not (fskv and (fskv.kv_set or fskv.set)) then
        log.warn("touch", "固件没有 fskv 库，标定系数不持久化")
        return false, "no fskv"
    end
    if not (json and json.encode) then
        log.warn("touch", "固件没有 json 库，标定系数不持久化")
        return false, "no json"
    end
    if not ensure_fskv() then
        return false, "fskv init failed"
    end
    local ok, s = pcall(json.encode, data)
    if not ok or type(s) ~= "string" then
        log.warn("touch", "标定系数序列化失败，不存档")
        return false, "encode failed"
    end
    local key = (M_CFG and M_CFG.cal_kv) or KV_KEY
    if kv_put(key, s) then
        log.info("touch", "标定系数已存档", key, "长度 " .. #s)
        return true
    end
    log.warn("touch", "fskv 写入失败", key)
    return false, "kv_set failed"
end

--[[从 fskv 取标定存档（只读不应用）
@return table data 存档存在且 json 合法时返回；否则 nil, 原因]]
function M.load_calibration()
    if not (fskv and (fskv.kv_get or fskv.get)) then
        return nil, "no fskv"
    end
    -- ★ 关键：读之前也必须 init kv 数据库（每次上电第一次），否则 kv_get 恒为 nil
    if not ensure_fskv() then
        return nil, "fskv init failed"
    end
    local key = (M_CFG and M_CFG.cal_kv) or KV_KEY
    local s = kv_read(key)
    if type(s) ~= "string" or s == "" then
        log.info("touch", "fskv 无标定存档", key, type(s))
        return nil, "not_saved"
    end
    if not (json and json.decode) then
        return nil, "no json"
    end
    local ok, data = pcall(json.decode, s)
    if not ok or type(data) ~= "table" then
        log.warn("touch", "标定存档损坏（json 解析失败）", "长度 " .. #s)
        return nil, "corrupt"
    end
    log.info("touch", "标定存档读取成功", key, "长度 " .. #s)
    return data
end

--[[删除标定存档（存档损坏/不合法时调用，避免每次上电读到坏数据）]]
function M.del_calibration()
    if fskv and (fskv.kv_del or fskv.del) and ensure_fskv() then
        local key = (M_CFG and M_CFG.cal_kv) or KV_KEY
        pcall(function() kv_drop(key) end)
        log.info("touch", "标定存档已删除", key)
    end
end

--[[上电恢复标定：fskv 取存档 → 回灌 tp（成功则可跳过四点标定）
@return boolean true=恢复成功（下一次触摸即用新参数）
@return string  err  false 时的原因（not_saved/corrupt/busy 超时/invalid_data/...）]]
function M.restore_calibration(timeout_ms)
    local data, err = M.load_calibration()
    if not data then
        if err == "corrupt" then M.del_calibration() end
        return false, err
    end
    local ok, aerr = M.apply_calibration(data, timeout_ms)
    if not ok then
        if aerr == "invalid_data" then
            log.warn("touch", "标定存档不合法（固件结构变了或数据坏），将作废重标")
            M.del_calibration()
        end
        return false, aerr
    end
    return true
end

--[[把 TP_STATE 快照成 poll 风格的表，界面逻辑与驱动来源解耦
    注意：tp 库已内置坐标映射（含标定），raw 行显示的就是映射后坐标]]
function M.sample()
    local s = TP_STATE
    local pressed = s.pressed
    return {
        ok = true,
        pressed = pressed,
        x = s.x, y = s.y,
        raw_x = s.x, raw_y = s.y,
        z1 = pressed and 2048 or 0, z2 = 0,
        err = 0,
    }
end

return M
