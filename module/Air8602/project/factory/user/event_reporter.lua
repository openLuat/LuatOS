--[[
@module  event_reporter
@summary 寄存柜事件记录（开箱 / 关箱 / 存件 / 取件 → 本地流水 CSV + 云端上报）
@version 1.0
@date    2026.09.29
@usage
    把柜体事件统一收口：先写本地流水，再上报云端（断网自动补传）。

    记录内容：
      1) 开箱（成功 / 失败）—— 来源：uart_controller 的 BOX_OPEN_RESULT
      2) 关箱（含开启时长）—— 来源：uart_controller 的 BOX_STATUS_UPDATE
         （锁板 81 主动上报、轮询读状态两条路径都会产生）
      3) 业务事件 —— 来源：ecbusiness 发布的 CABINET_EVENT
         （扫码存件 DEPOSIT / 取件码取件 PICKUP）

    去向：
      · 本地流水（主）：/sd/log/cabinet_event_YYYYMMDD.csv（SD 未挂载自动回退 /ram/log）
        列：时间,事件,说明,事件ID,柜号,设备号,业务标识,附加信息,照片,结果
        写盘在独立协程里异步完成，SD 卡慢/坏块不会阻塞开柜与界面刷新
      · 云端上报（开关 config.report.enabled）：aircloud.report_event() → excloud.send(TLV)
        断网时先落本地补传队列 /sd/log/pending_upload.jsonl，联网后自动补录（掉电不丢）

    订阅消息：
      BOX_OPEN_RESULT   {box_num=, success=}            开箱结果
      BOX_STATUS_UPDATE {{box=,open=},...}              门状态（关箱判定）
      CABINET_EVENT     {event=, box=, ident=, extra=}  业务事件
]]

local config = require "config"
local server_api = require "server_api"
local aircloud = require "aircloud"

local M = {}

-- 事件是否上云（false=只写本地 CSV）
local REPORT_ENABLED = config.get("report.enabled", true)

-- 本地流水目录（SD 未挂载时回退 /ram/log）
local function get_log_dir()
    local dir = config.get("report.local_log_dir", "/sd/log")
    if dir:sub(1, 3) == "/sd" then
        local sd_card = require "sd_card"
        local mounted = false
        pcall(function() mounted = sd_card.is_mounted() end)
        if not mounted then
            pcall(sd_card.init)    -- 任务上下文里再试挂一次
            pcall(function() mounted = sd_card.is_mounted() end)
        end
        if not mounted then
            dir = "/ram/log"
        end
    end
    return dir
end

-- 设备号（只取一次并缓存）
local cached_device_id = nil
local function get_device_id()
    if cached_device_id then return cached_device_id end
    local ok, v = pcall(function()
        return server_api.get_device_id and server_api.get_device_id()
    end)
    cached_device_id = (ok and v and v ~= "") and v or "unknown"
    return cached_device_id
end

-- 事件唯一 ID：设备号 + 本地持久化自增号（fskv，掉电保留）
-- 号段预占：每次向 fskv 预占 SEQ_BLOCK 个号，内存里顺序发号 ——
--   把"每条事件一次 flash 写"降为"每 SEQ_BLOCK 条一次"；掉电后从已预占的上界继续
local SEQ_BLOCK = 1000
local seq_next = nil
local seq_limit = nil

local function next_seq()
    if not seq_next or seq_next > seq_limit then
        local base = tonumber(fskv.get("evt_seq") or "0") or 0
        if base >= 99999999 then base = 0 end
        seq_next = base + 1
        seq_limit = base + SEQ_BLOCK
        fskv.set("evt_seq", tostring(seq_limit))
    end
    local n = seq_next
    seq_next = seq_next + 1
    return string.format("%s-%d", get_device_id(), n)
end

-- 事件中文说明（本地流水可读列）
local EVENT_TEXT = {
    OPEN = "开箱", CLOSE = "关箱",
    DEPOSIT = "扫码存件", PICKUP = "取件码取件",
}

-- 开箱记录：box → { ts, scene, ident }，用于关箱时计算开启时长
local open_records = {}

-- 待上报的开箱事件（延迟 2s 上报，给紧随其后的业务事件一个补场景的窗口）：box → evt
local pending_open = {}

-- ==================== 本地流水（CSV：异步写盘，绝不阻塞业务） ====================
-- 业务侧只调用 write_local_log() 入队；真正的文件 IO 在 local_log_task 协程里做，
-- 这样 SD 卡慢/坏块时也不会卡住消息循环（开柜、界面刷新）。
local LOG_QUEUE_MAX = 200     -- 内存队列上限（超出丢最旧，防无界增长）
local log_queue = {}
local log_task_running = false

-- 同步写一条（仅供 local_log_task 调用）
local function write_local_log_now(evt)
    local dir = get_log_dir()
    if not io.exists(dir) then
        pcall(io.mkdir, dir)
    end
    local path = string.format("%s/cabinet_event_%s.csv", dir, os.date("%Y%m%d"))
    local is_new = not io.exists(path)
    local f = io.open(path, "a")   -- 追加写
    if not f then
        log.warn("event_reporter", "本地流水打开失败:", path)
        return false, path
    end
    if is_new then
        f:write("时间,事件,说明,事件ID,柜号,设备号,业务标识,附加信息,照片,结果\r\n")
    end
    f:write(string.format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\r\n",
        os.date("%Y-%m-%d %H:%M:%S"),
        evt.event or "",
        EVENT_TEXT[evt.event] or "",
        tostring(evt.id or ""),
        tostring(evt.box or ""),
        tostring(evt.device_id or ""),
        tostring(evt.ident or ""),
        tostring(evt.extra or ""):gsub(",", " "),   -- CSV 防串列
        tostring(evt.photo_path or ""),
        tostring(evt.result or "ok")))
    f:close()
    return true, path
end

-- 写盘协程：逐条落盘（IO 全在这里做）；失败放回队首稍后重试，连续失败则丢弃该条并告警
local function local_log_task()
    local retry = 0
    while true do
        local evt = table.remove(log_queue, 1)
        if not evt then
            log_task_running = false
            return
        end
        if write_local_log_now(evt) then
            retry = 0
        else
            table.insert(log_queue, 1, evt)      -- 写失败：放回队首，稍后重试
            retry = retry + 1
            if retry > 3 then
                log.error("event_reporter", "本地流水连续写盘失败，丢弃该条:", tostring(evt.event))
                table.remove(log_queue, 1)
                retry = 0
            else
                sys.wait(3000)
            end
        end
        sys.wait(20)   -- 让出 CPU
    end
end

-- 入队（业务侧调用，立即返回，不等待任何 IO）
local function write_local_log(evt)
    table.insert(log_queue, evt)
    while #log_queue > LOG_QUEUE_MAX do
        table.remove(log_queue, 1)   -- 队列满：丢最旧
    end
    if not log_task_running then
        log_task_running = true
        sys.taskInit(local_log_task)
    end
    return true
end

-- 清理过期本地流水（按文件名里的日期判断）
local function cleanup_old_logs()
    local keep_days = config.get("report.local_log_keep_days", 30)
    if not keep_days or keep_days <= 0 then return end
    local dir = get_log_dir()
    local pok, list = pcall(io.lsdir, dir, 100, 0)
    if not pok or type(list) ~= "table" then return end
    local deadline = os.time() - keep_days * 86400
    local removed = 0
    for _, item in ipairs(list) do
        local name = (type(item) == "table" and item.name) or item
        local y, m, d = tostring(name):match("^cabinet_event_(%d%d%d%d)(%d%d)(%d%d)%.csv$")
        if y then
            local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
            if ts and ts < deadline then
                if io.exists(dir .. "/" .. name) then
                    pcall(os.remove, dir .. "/" .. name)
                    removed = removed + 1
                end
            end
        end
    end
    if removed > 0 then
        log.info("event_reporter", "已清理过期本地流水", removed, "个")
    end
end

-- ==================== 断网补传队列（先本地落盘，联网后补录云端） ====================
-- 队列文件每行一条 JSON：{type="event", ...}
--   · 云端未连接 / 上报失败 → 入队（掉电不丢，SD 未挂载时落 /ram/log）
--   · 联网后由 pending_upload_task 按序补传，成功一条删一条
local function pending_file()
    local path = config.get("report.pending.file", "/sd/log/pending_upload.jsonl")
    if path:sub(1, 3) == "/sd" then
        local dir = get_log_dir()          -- 复用：SD 未挂载时返回 /ram/log
        if dir ~= "/sd/log" then
            path = dir .. "/pending_upload.jsonl"
        end
    end
    return path
end

local function pending_load()
    local path = pending_file()
    if not io.exists(path) then return {} end
    local f = io.open(path, "r")
    if not f then return {} end
    local txt = f:read("*a") or ""
    f:close()
    local list = {}
    for line in txt:gmatch("[^\r\n]+") do
        local ok, item = pcall(json.decode, line)
        if ok and type(item) == "table" then
            table.insert(list, item)
        end
    end
    return list
end

local function pending_save(list)
    local path = pending_file()
    if #list == 0 then
        if io.exists(path) then pcall(os.remove, path) end
        return
    end
    local f = io.open(path, "w")
    if not f then
        log.warn("event_reporter", "补传队列写入失败:", path)
        return
    end
    for _, item in ipairs(list) do
        f:write(json.encode(item) .. "\r\n")
    end
    f:close()
end

-- 入队（超过 max_items 丢最旧，保证存储不会写满）
local function pending_append(item)
    local list = pending_load()
    table.insert(list, item)
    local max_items = config.get("report.pending.max_items", 500)
    local dropped = 0
    while #list > max_items do
        table.remove(list, 1)
        dropped = dropped + 1
    end
    pending_save(list)
    if dropped > 0 then
        log.warn("event_reporter", "补传队列超过上限，已丢弃最旧", dropped, "条")
    end
    return true
end

-- 逐条补传：成功一条删一条；遇到失败立即停止（保留剩余，下一轮再补）
local function flush_pending()
    if not REPORT_ENABLED then return 0 end
    local list = pending_load()
    if #list == 0 then return 0 end
    local sent = 0
    while #list > 0 do
        local item = list[1]
        local ok = aircloud.report_event({
            id = item.id,       -- 原样带回唯一 ID：云端按此幂等去重
            event = item.event, box = item.box,
            ident = item.ident, extra = item.extra, ts = item.ts,
        })
        if not ok then
            -- 连续失败次数过多（如字段不合法/被服务端拒绝）→ 丢弃该条
            item.fail = (item.fail or 0) + 1
            local max_fail = 10
            if item.fail >= max_fail then
                log.error("event_reporter", "补传连续失败 " .. max_fail .. " 次，丢弃该条:", tostring(item.event))
                table.remove(list, 1)
            end
            pending_save(list)
            break   -- 保留剩余记录，下一轮再补
        end
        table.remove(list, 1)
        sent = sent + 1
        pending_save(list)   -- 每条成功后立刻落盘
        sys.wait(200)        -- 每条之间留间隔
    end
    if sent > 0 then
        log.info("event_reporter", "断网补传完成", sent, "条，剩余", #list, "条")
    end
    return sent
end

-- ==================== 云端上报（独立协程，绝不阻塞业务） ====================
local function do_report(evt)
    if not REPORT_ENABLED then return end
    local payload = {
        id = evt.id,          -- 去重唯一 ID（断网补传时原样带回）
        event = evt.event,
        box = evt.box,
        ident = evt.ident,
        extra = evt.extra,
        ts = evt.ts,
    }
    -- 断网：不白等一次必然失败的发送，直接进补传队列
    if not aircloud.is_connected() then
        payload.type = "event"
        pending_append(payload)
        log.info("event_reporter", "云端未连接，事件已入补传队列:", tostring(evt.event))
        return
    end
    local ok = aircloud.report_event(payload)
    if not ok then
        payload.type = "event"
        pending_append(payload)
        log.warn("event_reporter", "事件上报失败，已入补传队列:", tostring(evt.event))
    end
end

-- ==================== 事件处理 ====================

-- 开箱结果（uart_controller 收到锁板 0x8A 反馈后发布）
local function on_box_open_result(data)
    if type(data) ~= "table" or not data.box_num then return end
    local box = tonumber(data.box_num) or data.box_num
    local now = os.time()
    local evt = {
        event = "OPEN",
        box = box,
        ts = now,
        device_id = get_device_id(),
        extra = string.format("ok=%d", data.success and 1 or 0),
        result = data.success and "ok" or "fail",
    }
    if not data.success then
        evt.extra = evt.extra .. ",err=" .. tostring(data.error or "开箱失败")
    else
        -- 记录开箱时刻，等门关闭（或超时）时算开启时长；
        -- 场景/业务标识由紧随其后的业务事件回填（见 on_cabinet_event）
        open_records[box] = { ts = now }
    end
    evt.id = next_seq()
    write_local_log(evt)
    -- 延迟 2s 再上报：给紧随其后的业务事件一个"补场景"的窗口（同一柜号）
    pending_open[box] = evt
    sys.taskInit(function()
        sys.wait(2000)
        local e = pending_open[box]
        if e then
            pending_open[box] = nil
            do_report(e)
        end
    end)
end

-- 门状态变化（锁板 81 主动上报 / 轮询读状态）：open==false 视为门已关 → 关箱事件
local function on_box_status(list)
    if type(list) ~= "table" then return end
    local now = os.time()
    for _, item in ipairs(list) do
        local box = item and item.box
        if box and item.open == false then
            local rec = open_records[box]
            if rec then
                local evt = {
                    event = "CLOSE",
                    box = box,
                    ts = now,
                    device_id = get_device_id(),
                    ident = rec.ident,
                    extra = string.format("dur=%ds,scene=%s,est=0", now - rec.ts, rec.scene or "unknown"),
                }
                evt.id = next_seq()
                open_records[box] = nil
                write_local_log(evt)
                sys.taskInit(do_report, evt)
            end
        end
    end
end

-- 业务事件：ecbusiness 发布 CABINET_EVENT 时一并记录
-- 新增事件类型时：在业务成功后 sys.publish("CABINET_EVENT", {event=, box=, ident=, extra=})
local function on_cabinet_event(evt)
    if type(evt) ~= "table" or type(evt.event) ~= "string" then return end
    local out = {
        event = evt.event,
        box = evt.box,
        ts = evt.ts or os.time(),
        device_id = get_device_id(),
        ident = evt.ident,
        extra = evt.extra,
        result = evt.result or "ok",
    }
    out.id = next_seq()
    -- 若该柜号的开箱事件还没上报出去，把业务场景补进去
    local pe = pending_open[out.box]
    if pe then
        pe.extra = string.format("scene=%s", tostring(out.extra or out.event))
    end
    -- 回填开箱记录的场景与业务标识：关箱行要用它们标注 dur/scene/ident
    local rec = out.box and open_records[out.box]
    if rec then
        rec.scene = out.extra or out.event
        rec.ident = out.ident
    end
    write_local_log(out)
    sys.taskInit(do_report, out)
end

-- ==================== 后台任务 ====================

-- 关箱超时兜底：开箱后 timeout 秒仍没等到"门关闭"，按估算记一条（est=1）
local function box_close_watchdog()
    local timeout = config.get("report.box_close.timeout", 60)
    if not timeout or timeout <= 0 then return end
    while true do
        sys.wait(5000)
        local now = os.time()
        for box, rec in pairs(open_records) do
            if now - rec.ts >= timeout then
                local evt = {
                    event = "CLOSE",
                    box = box,
                    ts = now,
                    device_id = get_device_id(),
                    ident = rec.ident,
                    extra = string.format("dur=%ds,scene=%s,est=1", now - rec.ts, rec.scene or "unknown"),
                    result = "timeout",
                }
                evt.id = next_seq()
                open_records[box] = nil
                write_local_log(evt)
                sys.taskInit(do_report, evt)
                log.warn("event_reporter", "柜" .. tostring(box) .. " 超时未见门关闭，按估算记录关箱")
            end
        end
    end
end

-- 轮询读锁状态（兜底锁板主动上报丢失；间隔见 config.report.box_close.poll_interval，0=不轮询）
local function box_status_poll_task()
    local interval = config.get("report.box_close.poll_interval", 5)
    if not interval or interval <= 0 then return end
    sys.wait(10000)   -- 开机先等系统与 485 总线起来
    while true do
        -- 按需轮询：只在"有柜子开着、还没确认关门"的窗口内去问锁板状态；
        -- 空闲（没有开箱记录）时一条命令都不发，不占用 485 总线。
        if next(open_records) then
            sys.publish("READ_BOX_STATUS")   -- uart_controller 已订阅该消息
            sys.wait(interval * 1000)
        else
            sys.wait(1000)
        end
    end
end

-- ==================== 订阅与对外接口 ====================

-- 断网补传任务：联网后把队列里的事件按序补录云端
local function pending_upload_task()
    if not REPORT_ENABLED then return end   -- 事件上云已关闭，无需补传任务
    local interval = config.get("report.pending.retry_interval", 30)
    if not interval or interval <= 0 then interval = 30 end
    sys.wait(20000)   -- 开机先等网络与 excloud 就绪
    while true do
        if aircloud.is_connected() then
            pcall(flush_pending)
        end
        sys.wait(interval * 1000)
    end
end

-- 云平台一连上就立刻补一次（不用等下一个轮询周期）
local function on_aircloud_connected()
    sys.taskInit(function()
        sys.wait(1000)   -- 等认证完成
        pcall(flush_pending)
    end)
end

sys.subscribe("BOX_OPEN_RESULT", on_box_open_result)
sys.subscribe("BOX_STATUS_UPDATE", on_box_status)
sys.subscribe("CABINET_EVENT", on_cabinet_event)
sys.subscribe("AIRCloud_CONNECTED", on_aircloud_connected)
sys.taskInit(box_close_watchdog)
sys.taskInit(box_status_poll_task)
sys.taskInit(pending_upload_task)

-- 对外接口：业务模块可直接调用记录一条事件
-- @param evt {event=, box=, ident=, extra=, result=}
function M.report(evt)
    on_cabinet_event(evt)
end

-- 模块初始化
-- ★ 注意：不能在 get_log_dir() 之前读 sd_card.is_mounted()。
--   main.lua 的 SD 挂载任务与这里是并发跑的，挂载要 300ms+，提前读会拿到 false，
--   于是打印出"SD 挂载=false"但目录却是 /sd/log 的自相矛盾日志（实际是挂上的）。
--   get_log_dir() 内部会在未挂载时补挂一次、仍失败才回退 /ram/log，
--   所以以它的结果（目录）判断 SD 是否可用才准确、无竞态。
--   （8601 工程的 event_reporter.init() 就是不读 is_mounted()，只打印 get_log_dir() 的结果。）
local function init()
    local dir = get_log_dir()
    log.info("event_reporter", "事件记录初始化：本地流水目录=" .. dir
        .. "，SD 挂载=" .. tostring(dir:sub(1, 3) == "/sd")
        .. "，事件上云=" .. tostring(REPORT_ENABLED))
    if not REPORT_ENABLED then
        -- 事件上云关闭：清掉可能残留的补传队列文件（本地 CSV 已有完整记录，不丢信息）
        local path = pending_file()
        if io.exists(path) then
            pcall(os.remove, path)
            log.info("event_reporter", "事件上云已关闭，已清理残留补传队列", path)
        end
    end
    cleanup_old_logs()
end
sys.taskInit(init)

return M
