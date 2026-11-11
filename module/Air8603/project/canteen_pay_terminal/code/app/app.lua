--[[
@module  app
@summary 业务主流程（状态机）· 示例工程，业务逻辑未改动

需求 1：阿姨在触摸屏输入金额 → 点确认 → 语音播报金额
需求 2：摄像头扫到任意二维码 → 本地判收款成功 → 左侧弹窗显示「收款成功 + 输入金额」并播报
需求 3：支付信息返回后端收费系统，由 config.pay.enable 控制，示例默认关（演示模式不发 HTTP）
需求 4：误按确认后、扣费前按 C 可取消，保留已输金额回到修改状态
需求 5：结果弹窗期间按任意键只关弹窗，不打断当前语音播报

流程：输入金额 → [确认] → 播报金额 → 等待扫码 → 弹收款成功 → 播报 → 4 秒停留 → 复位
取消：确认后至「扫码等待结束」之前按 C 立即回输入态（金额保留，再按 C 清空重输）
约束：不做权限校验、不回传图像/日志等额外信息（见 pay.lua / config.lua）
]]

local CFG   = require "config"
local HW    = require "hw_init"
local WIFI  = require "wifi"
local UI    = require "ui"
local VOICE = require "voice"
local SCAN  = require "scan"
local PAY   = require "pay"

local input = ""      -- 屏幕上正在输入的金额字符串，如 "12.35"
local seq   = 0       -- 本地流水号，断电不保存
local busy  = false   -- 一次交易进行中，忽略按键

-- ===== 取消相关状态（仅本文件使用） =====
-- cancel_armed : 「确认后 → 扫码等待结束前」的取消窗口，钱还没扣出去
-- cancel_req   : 窗口内是否按过 C
-- scan_card/got: 常驻订阅记录扫码结果，避免轮询间隙丢消息
local cancel_armed = false
local cancel_req   = false
local scan_card    = nil
local scan_stable  = nil   -- 备用键：横杠前的纯数字工牌 ID（仅供兜底路径）
local scan_got     = false

local function parse_fen(s)
    if not s or s == "" or s == "." then return 0 end
    local v = tonumber(s)
    if not v then return 0 end
    return math.floor(v * 100 + 0.5)
end

local function amount_str(fen)
    return string.format("%.2f", fen / 100)
end

-- 处理一次按键，返回 true 表示按下了「确认」
local function on_key(k)
    if busy then return false end
    if k == "C" then
        input = ""
    elseif k == "." then
        if input ~= "" and not input:find("%.") then input = input .. "." end
    elseif k == "OK" then
        return true
    elseif k:match("^%d$") then
        local dot = input:find("%.")
        if dot and (#input - dot) >= CFG.limit.max_decimals then return false end
        if #input >= 8 then return false end
        local next_input = input .. k
        if parse_fen(next_input) > CFG.limit.max_amount_fen then return false end
        input = next_input
    end
    UI.set_amount(UI.money(input == "" and "0.00" or input))
    return false
end

local function drain_keys()
    -- 交易期间按下的键不排队到下一笔，避免连续误触发
    while sys.waitUntil("UI_KEY", 10) do end
end

-- ===== 常驻事件订阅 =====
-- 交易期间主协程阻塞在 VOICE.say / sys.wait 里，on_key 不会被调用，
-- 所以 C 键与扫码结果都由这里的常驻函数回调收集（sys.publish 入队分发，不会丢）。
-- 输入态时 cancel_armed=false，回调什么都不做，C 仍由 on_key 负责清空。
sys.subscribe("UI_KEY", function(k)
    -- 结果弹窗期间：任意键只关弹窗。主协程此刻阻塞在 VOICE.say / 4 秒停留里，
    -- 没有订阅 UI_KEY，所以这个键不会进 on_key()，不会误输入金额或触发下一笔；
    -- 回调不碰 voice 模块，当前这句语音照常播完（含播完关 PA）。
    if UI.popup_visible() then
        UI.hide_pay_ok()
        log.info("app", "弹窗已关闭（按键）", k)
        return
    end
    if cancel_armed and not scan_got and not cancel_req and k == "C" then
        cancel_req = true
        UI.set_result("")
        UI.set_status("已取消，请重新输入金额（按 C 清空重输）")
        log.info("app", "交易取消请求")
    end
end)

sys.subscribe("SCAN_RESULT", function(card, stable)
    if cancel_armed and not cancel_req then
        scan_card, scan_stable, scan_got = card, stable, true
    end
end)

local function arm_cancel()
    cancel_req, scan_got, scan_card, scan_stable = false, false, nil, nil
    cancel_armed = true
end

-- 等扫码结果 / 取消 / 超时；返回 "scan" / "cancel" / nil
-- 用 sys.wait(100) 短等，常驻订阅负责收消息，避免 waitUntil 反复订阅的间隙丢事件
local function wait_scan_or_cancel(timeout_ms)
    local waited, POLL = 0, 100
    while waited < timeout_ms do
        if cancel_req then return "cancel" end
        if scan_got  then return "scan" end
        local step = math.min(POLL, timeout_ms - waited)
        sys.wait(step)
        waited = waited + step
    end
    if cancel_req then return "cancel" end
    if scan_got  then return "scan" end
    return nil
end

local function main_task()
    -- ===== 硬件 / 界面 / 网络 初始化 =====
    HW.init()
    UI.init()
    VOICE.setup()
    WIFI.start()

    UI.set_net("网络：连接中…")
    local cam_ok = SCAN.init()          -- 内含 3 秒等 USB 枚举
    if WIFI.wait_ready() then
        UI.set_net("网络：已连接")
    else
        UI.set_net("网络：未连接")
        log.warn("app", "WiFi 未就绪，扣费请求可能失败")
    end
    if not cam_ok then UI.set_status("摄像头未就绪，请检查 USB 接线") end
    UI.set_status("请输入金额，然后点确认")

    -- ===== 一次交易主体；返回 false 表示用户按 C 取消 =====
    local function do_trade(fen)
        arm_cancel()

        -- 需求 1：确认后播报金额（按 C 不打断当前这句，播完再检查）
        UI.set_status("金额确认，请听语音")
        VOICE.say("本次消费" .. VOICE.amount_text(fen))
        if cancel_req then return false end                       -- 检查点 A

        -- 需求 2：扫码 → 识别 ID → 扣费 → 播报结果
        UI.set_status("请将饭卡二维码对准摄像头，按 C 取消")
        VOICE.say("请扫码")
        if cancel_req then return false end                       -- 检查点 B

        local card, stable, ok_pay, pay_msg, info = nil, nil, false, "", nil
        if cam_ok and SCAN.start() then
            local what = wait_scan_or_cancel(CFG.limit.scan_timeout_ms)   -- 检查点 C
            cancel_armed = false                                  -- 检查点 D：扫码阶段结束，关闭取消窗口
            SCAN.stop()
            if what == "cancel" then
                return false
            elseif what == "scan" then
                card, stable = scan_card, scan_stable
                UI.set_status("扫码成功")
                seq = seq + 1
                if CFG.pay.enable then
                    ok_pay, info, pay_msg = PAY.deduct(card, fen, seq, stable)
                else
                    -- 演示模式：扫到任意码即本地判成功，不发 HTTP，占位地址不再报 -8
                    ok_pay, info, pay_msg = true, nil, ""
                    log.info("app", "本地收款模式 pay.enable=false，跳过 HTTP 扣费")
                end
                if ok_pay then
                    local money = UI.money(amount_str(fen))
                    UI.set_result("收款成功  " .. money)  -- 弹窗关掉后结果栏仍可见
                    local bal_txt = ""
                    if info and info.balanceFen then
                        bal_txt = "余额 " .. UI.money(amount_str(info.balanceFen))
                    end
                    UI.show_pay_ok(money, bal_txt)        -- 必须先弹窗，再播报
                    VOICE.say("收款成功" .. VOICE.amount_text(fen))
                    if info and info.balanceFen then
                        VOICE.say("当前余额" .. VOICE.amount_text(info.balanceFen))
                    end
                else
                    local why = (pay_msg and pay_msg ~= "") and pay_msg or "请重试"
                    VOICE.say("扣费失败，" .. why)
                    UI.set_result("扣费失败：" .. why)
                end
            else
                pay_msg = "扫码超时"
                VOICE.say("扫码超时，请重试")
                UI.set_result("扫码超时，请重试")
            end
        else
            cancel_armed = false
            pay_msg = "摄像头不可用"
            VOICE.say("摄像头不可用，请联系管理员")
            UI.set_result("摄像头不可用")
        end

        -- 需求 3：支付信息返回后端收费系统（仅开关打开时；失败不影响本地已播报的结果）
        if CFG.pay.enable and card then
            PAY.report(card, fen, info and info.tradeId, ok_pay, pay_msg)
        end

        cancel_armed = false
        return true
    end

    -- ===== 主循环 =====
    while true do
        local _, key = sys.waitUntil("UI_KEY")
        local confirm = on_key(key)

        if confirm then
            local fen = parse_fen(input)
            if fen <= 0 then
                UI.set_status("请先输入金额")
            else
                busy = true
                log.info("app", "交易开始 金额(分)", fen)

                local finished = do_trade(fen)

                if finished then
                    sys.wait(CFG.limit.result_hold_ms)
                    input = ""
                    UI.set_amount(UI.money("0.00"))
                    UI.set_result("")
                    UI.set_status("请输入金额，然后点确认")
                else
                    -- 取消：不扣费、不回传、不等结果停留；金额原样保留，回到「重新修改」
                    SCAN.stop()
                    cancel_armed, cancel_req = false, false
                    scan_got, scan_card = false, nil
                    UI.set_result("")
                    UI.set_status("已取消，请重新输入金额（按 C 清空重输）")
                    UI.set_amount(UI.money(input == "" and "0.00" or input))
                end

                -- 弹窗覆盖整个结果阶段（语音 + 4 秒停留）；无论是否被按键提前关掉，
                -- 回到输入态前统一再隐藏一次，防止残留
                UI.hide_pay_ok()
                drain_keys()
                busy = false
                log.info("app", finished and "交易结束，回到输入态" or "交易已取消，回到输入态")
            end
        end
    end
end

sys.taskInit(main_task)
