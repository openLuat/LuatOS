--[[
@module  pay
@summary 对接示例后端（表单型开放 API v5）食堂刷卡接口
@note    示例协议（请以自己的接口文档为准）：
         ① 查员工 -> B2 查询多条  POST /api/v5/app/entry/data/list
            按接口示例用「识别有效位数」number 字段过滤，一次取回 nametext + balance
         ② 记消费 -> A1 新建单条  POST /api/v5/app/entry/data/create
            姓名写查到的 nametext，不再由设备端硬编码映射
         请求头：Authorization = Bearer <api_key>，Content-Type = application/json
         演示模式(CFG.pay.enable=false，示例默认)下 app.lua 不调用本模块，直接判收款成功。

         ★ 余额由后端维护（示例方案）：本模块只读 balance、只追加消费流水，
           不会调用任何更新接口。后台需配「消费表新增 → 更新员工表 balance」，
           否则连续两笔都从同一个余额起算。
]]

local CFG = require "config"
local M = {}

-- ★ 设备 RTC 未校时，os.time() 从 2020-01-01 起算，直接写进 time 会得到
--   "2020-01-01T00:09:22.000Z" 这类脏数据（与服务器 createTime 差 6 年）。
--   改用 HTTP 响应头 Date（标准 GMT）作为交易时间：每笔交易的 list
--   请求顺带取一次，误差 < 1 秒，无需 SNTP / 额外请求 / 不依赖设备时钟。
local MONTH = { Jan="01", Feb="02", Mar="03", Apr="04", May="05", Jun="06",
                Jul="07", Aug="08", Sep="09", Oct="10", Nov="11", Dec="12" }
local server_time_iso = nil

local function http_date_to_iso(h)
    if type(h) ~= "string" then return nil end
    local dd, mon, yy, hh, mm, ss =
        h:match("%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+)")
    local m = MONTH[mon]
    if not (dd and m and yy and hh and mm and ss) then return nil end
    return string.format("%s-%s-%02dT%02d:%02d:%02d.000Z",
        yy, m, tonumber(dd), tonumber(hh), tonumber(mm), tonumber(ss))
end

-- 通用 POST：带鉴权头，返回 (data表 或 nil, 错误信息)
local function http_post(path, tbl)
    local j = CFG.jdy
    -- 未填 API Key 时的提示：屏幕/语音只显示短句（结果栏一行放不下长文本）；
    -- 完整填写位置见 config/config.lua 的 C.jdy.api_key，串口日志另有 POST 记录可查。
    if not j or not j.api_key or j.api_key == "" then
        return nil, "未配置 API Key"
    end
    local url  = j.base_url .. path
    local body = json.encode(tbl)
    log.info("pay", "POST", url, body)
    local code, headers, resp = http.request(
        "POST", url,
        { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. j.api_key },
        body,
        { timeout = CFG.pay.timeout_ms }
    ).wait()
    if type(headers) == "table" then   -- 缓存服务器时间，供本笔 create 的 time 字段使用
        local iso = http_date_to_iso(headers.Date or headers.date)
        if iso then
            server_time_iso = iso
            log.info("pay", "服务器时间", iso)
        end
    end
    log.info("pay", "HTTP", code, resp and resp:sub(1, 300) or "nil")
    if code ~= 200 then
        return nil, "HTTP " .. tostring(code)
    end
    local data = (resp and #resp > 0) and json.decode(resp) or nil
    return data, nil
end

-- 账户键 → 员工姓名(nametext)【兜底路径，默认停用】
-- 接口已提供「识别有效位数」(number) 字段，正常路径直接按 number 查员工表，
-- 不需要手工映射。仅当 C.jdy.fallback_to_name=true 且按 number 查不到时才走这里。
-- 未登记且不是纯中文姓名的键一律拒绝，避免把识别码当姓名查、扣错人。
local function resolve_name(card, stable)
    local m = CFG.jdy.account_map
    -- ① 主账户键（按 C.card.parse_rule 提取）
    if m and type(card) == "string" and m[card] then return m[card] end
    -- ② 备用键（横杠前纯数字工牌 ID）：老映射表按它登记过，兜底时再试一次
    if m and type(stable) == "string" and stable ~= "" and m[stable] then return m[stable] end
    if type(card) ~= "string" or card == "" then
        return nil, "账户未登记"
    end
    -- ③ 兼容旧饭卡：二维码内容本身就是纯中文姓名（UTF-8 每个字节都 >= 0x80）
    local pure_cn = true
    for i = 1, #card do
        if card:byte(i) < 128 then
            pure_cn = false
            break
        end
    end
    if pure_cn and #card >= 6 then return card end
    return nil, "账户未登记"
end

-- ▲【按需 O09】自建后端协议不同时，改本文件两处 http_post 的路径与请求体：
--              下面 query_employee_by_number 的 /list，以及 create_payment 的 /create。
-- ① 主路径：按接口示例用「识别有效位数」(number) 过滤员工表，
--    一次拿回姓名(nametext) 与余额(balance)，避免把消费记到别人名下。
--    返回 (name, balance, nil) 或 (nil, nil, err)
local function query_employee_by_number(card)
    local j = CFG.jdy
    local data, err = http_post("/api/v5/app/entry/data/list", {
        app_id   = j.app_id,
        entry_id = j.emp_entry_id,
        fields   = { j.emp_balance_field, j.emp_name_field },
        filter   = {
            rel  = "and",
            cond = {
                { field = j.emp_number_field, type = "text", method = "eq", value = { card } }
            }
        }
    })
    if not data then return nil, nil, err or "查询失败" end
    local rows = data and data.data
    if type(rows) ~= "table" or #rows == 0 then
        return nil, nil, "未登记识别码"
    end
    if #rows > 1 then
        log.warn("pay", "识别有效位数重复", card, "命中", #rows, "条，拒绝扣费")
        return nil, nil, "账户重复"
    end
    local row  = rows[1]
    local name = row[j.emp_name_field]
    if type(name) ~= "string" or name == "" then
        return nil, nil, "姓名缺失"
    end
    
    local bal = tonumber(row[j.emp_balance_field])
    if not bal then
        return nil, nil, "余额字段异常"
    end
    log.info("pay", "按识别码命中员工", name, "读到余额(元)", bal)
    return name, bal, nil
end

-- 兜底：按姓名查余额（仅 C.jdy.fallback_to_name=true 时使用）
local function query_balance(name)
    local j = CFG.jdy
    local data, err = http_post("/api/v5/app/entry/data/list", {
        app_id   = j.app_id,
        entry_id = j.emp_entry_id,
        fields   = { j.emp_balance_field },
        filter   = {
            rel  = "and",
            cond = {
                { field = j.emp_match_field, type = "text", method = "eq", value = { name } }
            }
        }
    })
    if not data then return nil, err or "查询失败" end
    local rows = data and data.data
    if type(rows) ~= "table" or #rows == 0 then
        return nil, "未找到员工：" .. tostring(name)
    end
    -- 示例方案：余额由后端（公式/自动化）维护时，公式字段可能返回字符串
    -- "129.5" 而非数字，这里统一 tonumber 兜底，避免设备报「余额字段异常」收不了款。
    local bal = tonumber(rows[1][j.emp_balance_field])
    if not bal then
        return nil, "余额字段(" .. j.emp_balance_field .. ")异常"
    end
    log.info("pay", "读到余额(元)", bal)
    return bal, nil
end

-- ② 记消费：往消费表单新建一条记录，返回新记录 _id 或 nil+err
-- ▲【按需 O09】← 下面的 /create 路径与 data 字段，自建后端时在这里改
local function create_payment(name, amount_fen)
    local j = CFG.jdy
    local amount_yuan = tonumber(string.format("%.2f", amount_fen / 100))  -- 分 -> 元，去掉浮点尾数
    local data, err = http_post("/api/v5/app/entry/data/create", {
        app_id   = j.app_id,
        entry_id = j.pay_entry_id,
        data     = {
            ["type"]        = { value = j.consume_type },
            ["consume"]     = { value = amount_yuan },
            -- 优先用服务器时间；万一拿不到 Date 头才退回设备时钟（此时日志可据此排查）
            ["time"]        = { value = server_time_iso
                                      or os.date("!%Y-%m-%dT%H:%M:%S.000Z", os.time()) },
            ["nametext"]    = { value = name },
        }
    })
    if not data then return nil, err or "记账失败" end
    return (data.data and data.data._id) or "ok", nil
end

--[[ 系统扣费（被 app.lua 调用）
返回 (ok, info, msg)
  ok=false, msg                            -> 弹「扣费失败，xxx」
  ok=true,  info={tradeId, balanceFen}     -> 弹「收款成功」并展示新余额
顺序：按 number 查员工(姓名+余额) -> 不足直接失败(不写记录) -> 足够才记消费。
]]
function M.deduct(card_id, amount_fen, seq, stable_id)
    local j = CFG.jdy
    if type(card_id) ~= "string" or card_id == "" then
        return false, nil, "账户未登记"
    end

    -- ① 主路径：按接口示例用「识别有效位数」查员工，姓名与余额都取自同一条记录
    local name, bal, err = query_employee_by_number(card_id)

    -- ② 可选兜底：员工表尚未录入 number 时，才允许走旧的姓名映射
    --    默认关闭（fallback_to_name=false），避免把别人的消费记到旧映射的人头上
    if not name and j.fallback_to_name then
        local alt, rerr = resolve_name(card_id, stable_id)
        if alt then
            local b2, e2 = query_balance(alt)
            if b2 then
                log.info("pay", "回退按姓名命中", alt)
                name, bal, err = alt, b2, nil
            else
                err = e2 or err
            end
        else
            log.info("pay", "回退未命中", rerr or "")
        end
    end
    if not name then
        return false, nil, err or "账户未登记"
    end

    if bal < amount_fen / 100 then
        return false, nil, "余额不足"
    end
    local trade_id, cerr = create_payment(name, amount_fen)
    if not trade_id then
        return false, nil, cerr
    end
    local new_bal_fen = math.floor((bal - amount_fen / 100) * 100 + 0.5)
    return true, { tradeId = trade_id, balanceFen = new_bal_fen, name = name }, nil
end

-- 原「支付信息回传」已由 create 一步完成（消费记录本身即回传），此处留空实现。
function M.report(card_id, amount_fen, trade_id, result, message)
    return true
end

return M
