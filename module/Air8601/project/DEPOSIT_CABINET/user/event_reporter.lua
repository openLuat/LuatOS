--[[
@module  event_reporter
@summary 寄存柜事件上报（云端 excloud + 本地流水）与照片上传
@version 1.0
@date    2026.09.27
@author  王城钧
@usage
统一收口三类信息：
  1) 开箱 / 关箱（含开启时长）—— 来源：uart_controller 的 BOX_OPEN_RESULT、BOX_STATUS_UPDATE
  2) 业务事件（刷脸存件/刷脸取件/扫码存件/取件码取件）—— 来源：ecbusiness 发布的 CABINET_EVENT
  3) 人脸照片 —— 来源：ecface 存盘后发布的 FACE_PHOTO_SAVED（仅刷脸场景）

去向：
  · 本地流水（主）：/sd/log/cabinet_event_YYYYMMDD.csv（SD 未挂载回退 /ram/log）
      列：时间,事件,说明,事件ID,柜号,设备号,业务标识,附加信息,照片,结果
      · 开箱/关箱/存件/取件等【事件】是否上云由 config.report.enabled 决定（当前为 true）；
        关闭时只写本地 CSV，客户可自行把 CSV 取走上云，本地流水始终是完整记录，断网/关机都不丢。
  · 云端照片：aircloud.upload_photo() → excloud.upload_image(路径, 名字)
      ★ 只有 FACE_STORE / FACE_PICKUP 才上传照片；OPEN/CLOSE/DEPOSIT/PICKUP 一律不带照片
  · 云端事件：aircloud.report_event() → excloud.send(TLV)
      开关见 config.report.enabled；关闭时不入队、不产生补传文件

对外消息：
  订阅 BOX_OPEN_RESULT   {box_num=, success=}    开箱结果（uart_controller 已有）
  订阅 BOX_STATUS_UPDATE {{box=,open=},...}      门状态（uart_controller PUSH/轮询）
  订阅 CABINET_EVENT     {event=, box=, ident=, extra=}  业务事件（由 ecbusiness 发）
  订阅 FACE_PHOTO_SAVED  {path=, mode=}          人脸照片已落盘（由 ecface 发）

注意：
  1. 所有上报都在独立协程中异步执行，网络慢/断网不会阻塞开柜等业务；
  2. 本地流水先写盘、再上报云端，保证断网也不丢记录；
  3. 照片上传失败按 config.report.photo_retry 重试，仍失败则仅保留本地照片。
]]

local config = require "config"
local aircloud = require "aircloud"
local server_api = require "server_api"

local M = {}

local REPORT_ENABLED = config.get("report.enabled", true)
local PHOTO_ENABLED = config.get("report.upload_photo", true)

-- 最近一次人脸照片（仅刷脸场景更新；业务事件到来时取用，超时作废）
local last_photo = { path = nil, ts = 0, ttl_ms = 5 * 60 * 1000 }

-- 开箱记录：box → { ts, scene, ident, reported }
local open_records = {}

-- 待上报的开箱事件（延迟 2s 上报，供业务事件补场景）：box → evt
local pending_open = {}

-- 照片上传队列（异步，元素 {path=, name=, retry=}）
local photo_queue = {}

-- ==================== 工具函数 ====================

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

-- 事件唯一 ID（云端去重用）：设备号 + 本地持久化自增号（fskv，掉电保留）
--   ★ 同一事件在"直传"和"断网补传"时用的是同一个 ID，云端按 ID 幂等去重
-- 号段预占：每次向 fskv 预占 SEQ_BLOCK 个号，内存里顺序发号 ——
--   把每条事件一次 flash 写降为每 SEQ_BLOCK 条一次；掉电后从已预占的上界继续
local SEQ_BLOCK = 1000
local seq_next = nil     -- 下一个可用号
local seq_limit = nil    -- 当前号段上界

local function next_seq()
    if not seq_next or seq_next > seq_limit then
        local base = tonumber(fskv.get("evt_seq") or "0") or 0
        if base >= 99999999 then base = 0 end
        seq_next = base + 1
        seq_limit = base + SEQ_BLOCK
        fskv.set("evt_seq", tostring(seq_limit))   -- 预占本段（写 flash 频率 1/SEQ_BLOCK）
    end
    local n = seq_next
    seq_next = seq_next + 1
    return string.format("%s-%d", get_device_id(), n)
end

-- 本地流水目录（SD 未挂载时回退 /ram/log）
local function get_log_dir()
    local dir = config.get("report.local_log_dir", "/sd/log")
    if dir:sub(1, 3) == "/sd" then
        local sd_card = require "sd_card"
        local mounted = false
        pcall(function() mounted = sd_card.is_mounted() end)
        if not mounted then
            pcall(sd_card.init)   -- 任务上下文里再试挂一次
            pcall(function() mounted = sd_card.is_mounted() end)
        end
        if not mounted then
            dir = "/ram/log"
        end
    end
    return dir
end

-- 开箱事件的 scene/ident 由紧随其后的业务事件回填
--     （见 on_cabinet_event：pe.extra / rec.scene 两处）

-- 只有刷脸场景才会上传照片（普通存件/取件码取件/开箱/关箱一律不带）
local function need_photo(event)
    return event == "FACE_STORE" or event == "FACE_PICKUP"
end

-- 事件中文说明（本地流水可读列）
local EVENT_TEXT = {
    OPEN = "开箱", CLOSE = "关箱",
    FACE_STORE = "刷脸存件", FACE_PICKUP = "刷脸取件",
    DEPOSIT = "扫码存件", PICKUP = "取件码取件", FACE_FAIL = "刷脸失败",
}

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
    -- 顺带清理过期留底照片（策略见 config.face.photo.keep_days / max_count）
    pcall(function()
        require("face_photo").cleanup()
    end)
end

-- ==================== 断网补传队列（先本地落盘，联网后补录云端） ====================
-- 队列文件每行一条 JSON：{type="event"/"photo", ...}
--   · 云端未连接 / 上报失败 → 入队（掉电不丢，SD 未挂载时落 /ram）
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

-- 逐条补传：成功一条删一条；遇到失败立即停止
local function flush_pending()
    if not REPORT_ENABLED then return 0 end
    local list = pending_load()
    if #list == 0 then return 0 end
    local sent = 0
    while #list > 0 do
        local item = list[1]

        -- 照片已被删除/丢失：直接丢弃该条
        if item.type == "photo" and not io.exists(item.path) then
            log.warn("event_reporter", "补传照片文件不存在，丢弃该条:", tostring(item.path))
            table.remove(list, 1)
            pending_save(list)
        else
            local ok = false
            if item.type == "photo" then
                ok = aircloud.upload_photo(item.path, item.name)
            else
                ok = aircloud.report_event({
                    id = item.id,       -- 原样带回唯一 ID：云端按此幂等去重
                    event = item.event, box = item.box,
                    ident = item.ident, extra = item.extra, ts = item.ts,
                })
            end
            if not ok then
                -- 连续失败次数过多（如字段不合法/被服务端拒绝）→ 丢弃该条
                item.fail = (item.fail or 0) + 1
                local max_fail = 10
                if item.fail >= max_fail then
                    log.error("event_reporter", "补传连续失败 " .. max_fail .. " 次，丢弃该条:", tostring(item.type))
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
    end
    if sent > 0 then
        log.info("event_reporter", "断网补传完成", sent, "条，剩余", #list, "条")
    end
    return sent
end

-- ==================== 云端上报（独立协程，绝不阻塞业务） ====================
local function do_report(evt)
    if not REPORT_ENABLED then
        return
    end
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

-- 照片上传队列（串行 + 重试；失败不影响业务，照片本地仍在）
-- 错峰与降级策略：
--   照片约 8KB，经 airlink(UART3) 桥上传播时属于大帧；与事件 TLV / HTTP 响应挤在同一时刻，
--   会把 UART3 FIFO 打爆（uart3 err → airlink 数据长度错误 → link down → 断网）。
--   ① 队列首张先等 PHOTO_FIRST_DELAY 再传；② 上传前若网络已断，直接入补传队列；
--   ③ 重试间隔采用 PHOTO_RETRY_WAIT。
local PHOTO_FIRST_DELAY = 5000   -- 队列首张照片的错峰延时(ms)
local PHOTO_RETRY_WAIT = 8000    -- 照片上传重试间隔(ms)
local photo_task_running = false
local function photo_upload_task()
    local first = true
    while true do
        local item = table.remove(photo_queue, 1)
        if not item then
            photo_task_running = false
            return
        end
        if first then
            first = false
            sys.wait(PHOTO_FIRST_DELAY)   -- 错峰等待
        end
        if not socket.adapter(socket.dft()) or not aircloud.is_connected() then
            -- 网络已断：直接进补传队列（等联网后自动补传）
            pending_append({ type = "photo", path = item.path, name = item.name, ts = os.time() })
            log.warn("event_reporter", "网络未就绪，照片已入补传队列:", item.path)
        else
            local retry_max = config.get("report.photo_retry", 2)
            local ok, err = aircloud.upload_photo(item.path, item.name)
            if ok then
                log.info("event_reporter", "照片已上传云平台", item.path, item.name)
            elseif (item.retry or 0) < retry_max and socket.adapter(socket.dft()) then
                item.retry = (item.retry or 0) + 1
                table.insert(photo_queue, item)   -- 排到队尾重试
                log.warn("event_reporter", "照片上传失败，第 " .. item.retry .. " 次重试:", tostring(err))
                sys.wait(PHOTO_RETRY_WAIT)
            else
                -- 重试仍失败/链路已断：进补传队列
                pending_append({ type = "photo", path = item.path, name = item.name, ts = os.time() })
                log.warn("event_reporter", "照片上传失败，已入补传队列:", item.path, tostring(err))
            end
        end
        sys.wait(200)   -- 两张之间留间隔
    end
end

local function enqueue_photo(path, name)
    if not PHOTO_ENABLED or type(path) ~= "string" or path == "" then return end
    table.insert(photo_queue, { path = path, name = name, retry = 0 })
    if not photo_task_running then
        photo_task_running = true
        sys.taskInit(photo_upload_task)
    end
end

-- ==================== 事件处理 ====================

-- 开箱结果（uart_controller 发出 0x8A 命令后立即发布 BOX_OPEN_RESULT）
local function on_box_open_result(data)
    if type(data) ~= "table" or not data.box_num then return end
    local box = tonumber(data.box_num) or data.box_num
    local evt = {
        event = "OPEN",
        box = box,
        ts = os.time(),
        device_id = get_device_id(),
        extra = string.format("ok=%d", data.success and 1 or 0),
        result = data.success and "ok" or "fail",
    }
    if not data.success then
        evt.extra = evt.extra .. ",err=" .. tostring(data.error or "开箱失败")
    else
        -- 记录开箱时刻，等门关闭（或超时）时算开启时长；
        -- scene/ident 由紧随其后的业务事件回填（见 on_cabinet_event）
        open_records[box] = { ts = evt.ts }
    end
    evt.id = next_seq()   -- 唯一 ID：同一事件直传/补传都用它，云端据此去重
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
                evt.id = next_seq()   -- 唯一 ID：云端据此去重
                open_records[box] = nil
                write_local_log(evt)
                sys.taskInit(do_report, evt)
            end
        end
    end
end

-- 业务事件（ecbusiness 在业务成功后发布；只有刷脸事件才带照片）
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
    out.id = next_seq()   -- 唯一 ID：同一事件直传/补传都用它，云端据此去重
    if need_photo(out.event) then
        local fresh = last_photo.path and io.exists(last_photo.path)
            and (os.time() - (last_photo.ts or 0)) * 1000 <= last_photo.ttl_ms
        if fresh then
            out.photo_path = last_photo.path
        else
            log.warn("event_reporter", "刷脸事件无可用照片，仅上报事件:", out.event)
        end
    end
    -- 若该柜号的开箱事件还没上报出去，把业务场景补进去
    local pe = pending_open[out.box]
    if pe then
        pe.extra = string.format("scene=%s", tostring(out.extra or out.event))
    end
    -- 同时回填"开箱记录"的场景与业务标识：关箱事件（CLOSE）要用它们标注 dur/scene/ident，
    --   只填 pending_open 不够 —— open_records 缺 scene/ident 时，本地流水里关箱行的
    --   scene 会是 unknown、ident 会是空。
    local rec = out.box and open_records[out.box]
    if rec then
        rec.scene = out.extra or out.event
        rec.ident = out.ident
    end
    write_local_log(out)
    sys.taskInit(do_report, out)
    if out.photo_path then
        enqueue_photo(out.photo_path,
            string.format("%s_box%s_%s.jpg", out.event, tostring(out.box or 0), os.date("%Y%m%d_%H%M%S")))
    end
end

-- 人脸照片已落盘（ecface 拍照留底后发布；只有刷脸场景会发这条消息）
local function on_face_photo_saved(data)
    if type(data) ~= "table" or type(data.path) ~= "string" or data.path == "" then return end
    last_photo.path = data.path
    last_photo.ts = os.time()
    log.info("event_reporter", "登记待上传人脸照片", data.path, tostring(data.mode))
end

-- 业务上下文（ecbusiness 在开箱前发布，用于给开箱事件标注场景与业务标识）
-- 注：不能用未声明 local 的全局变量来传递场景（既是死代码又污染 _G），
--     场景标注统一由 on_cabinet_event 通过 pending_open / open_records 回填，
--     这里只保留日志便于定位问题。
local function on_cabinet_scene(data)
    if type(data) ~= "table" then return end
    log.debug("event_reporter", "业务上下文", tostring(data.scene), tostring(data.ident))
end

-- ==================== 后台任务 ====================

-- 关箱超时兜底：开箱后 timeout 秒仍没等到"门关闭"，按估算上报一条（est=1）
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
                evt.id = next_seq()   -- 唯一 ID：云端据此去重
                open_records[box] = nil
                write_local_log(evt)
                sys.taskInit(do_report, evt)
                log.warn("event_reporter", "柜" .. tostring(box) .. " 超时未见门关闭，按估算上报关箱")
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
        sys.publish("READ_BOX_STATUS")   -- uart_controller 已订阅该消息
        sys.wait(interval * 1000)
    end
end

-- 断网补传任务：联网后把队列里的事件/照片按序补录云端
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

sys.subscribe("CABINET_SCENE", on_cabinet_scene)
sys.subscribe("AIRCloud_CONNECTED", on_aircloud_connected)
sys.subscribe("BOX_OPEN_RESULT", on_box_open_result)
sys.subscribe("BOX_STATUS_UPDATE", on_box_status)
sys.subscribe("CABINET_EVENT", on_cabinet_event)
sys.subscribe("FACE_PHOTO_SAVED", on_face_photo_saved)
sys.taskInit(box_close_watchdog)
sys.taskInit(box_status_poll_task)
sys.taskInit(pending_upload_task)

-- 对外接口：业务模块直接调用
-- @param evt {event=, box=, ident=, extra=, result=}
function M.report(evt)
    on_cabinet_event(evt)
end

-- 开箱前设置业务上下文（scene: face_store/face_pickup/deposit/pickup/server_cmd）
function M.set_scene(scene, ident)
    on_cabinet_scene({ scene = scene, ident = ident })
end

-- 模块初始化
local function init()
    log.info("event_reporter", "事件上报模块初始化：事件上云=" .. tostring(REPORT_ENABLED)
        .. "，照片上云=" .. tostring(PHOTO_ENABLED) .. "，本地流水目录=" .. get_log_dir())
    if not REPORT_ENABLED then
        -- 事件上云关闭：清掉可能残留的补传队列文件（本地 CSV 已有完整记录，不会丢信息）
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
