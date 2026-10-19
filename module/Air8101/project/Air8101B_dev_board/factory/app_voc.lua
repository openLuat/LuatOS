--[[
@module  app_voc
@summary 空气质量业务层：AirVOC_1000（AGS02MA，0x1A）TVOC 周期采集 + 状态广播
@version 1.0
@date    2026.10.16
@usage
    local app_voc = require "app_voc"
    app_voc.start()        -- 在 task 中调用：open + 探测 + 周期采集
    app_voc.read_once()    -- 手动读一次（页面"立即读取"用，需在 task 中）
    app_voc.get()          -- { ppb=, ppm=, level=, desc=, ts= }，未采到过返回 nil
    app_voc.status()       -- "ok" / "init" / "not-found" / "read-error" / "open-error"
    app_voc.interval()     -- 当前采集间隔 ms（config 值套用下限后）
    app_voc.retry()        -- 重新 open + 探测（换线/换模块后用）

驱动
    官方驱动 AirVOC_1000.lua（LuatOS demo: module/Air8101/demo/accessory_board/AirVOC_1000），
    改造点：open() 可不传总线（复用本工程软 I2C 排针），另加 read() / probe()。

接线与总线
    与 AirSHT30_1000 同一排针：软 I2C，SCL=GPIO38 / SDA=GPIO39，与 GT911 触摸共用一条总线；
    器件地址 0x1A（AGS02MA 固定，不可配）。总线与采集间隔来自 config.hw.voc。

说明
1. 采集间隔默认 5000ms（5 秒，config.hw.voc.interval），代码下限 1500ms —— AGS02MA 数据约
   1.5 秒更新一次，读更快没有意义，还白占与触摸共用的总线；
2. 采到就发布 "VOC_UPDATE"（ppb, ppm, level, desc），失败发布 "VOC_ERROR"（原因, 连续失败次数）；
3. 触摸 / SHT30 / VOC 三条设备串行使用同一条软 I2C 总线，采集间隔别调太小；
4. AGS02MA 上电需要预热，前一两分钟读数漂移属正常现象；
5. AGS02MA 要求主机 I2C 时钟 ≤30kHz，比 GT911/SHT30 苛刻得多（快了直接不应答）：
   选中的配件板是空气质量时，drv_i2c 会把整条软 I2C 降到 config.hw.voc.i2c_delay
   （20µs ≈ 25kHz，触摸同速率，帧率略降属正常）；
6. 上电探测失败不判死：预热期本来就可能不响应，后台每 5 秒重试，最多 1 分钟；
7. 读失败原因分三类（no-ack / no-data / crc，见 AirVOC_1000.last_error），日志会打出来，
   三类排查方向完全不同；软 I2C 下 i2c.send 探地址会"假 ACK"，不能用来判断器件在不在。
]]

local voc = require "AirVOC_1000"

local M = {}

local latest      -- { ppb =, ppm =, level =, desc =, ts = 时间戳 }
local status = "init"
local fail_count = 0

local function cfg()
    return ((_G.project_config or {}).hw or {}).voc or {}
end

function M.get()
    return latest
end

function M.status()
    return status
end

function M.fail_count()
    return fail_count
end

function M.interval()
    local interval = tonumber(cfg().interval) or 5000
    if interval < 1500 then interval = 1500 end
    return interval
end

function M.read_once()
    local ppb, ppm, level, desc = voc.read()

    if ppb then
        latest = { ppb = ppb, ppm = ppm, level = level, desc = desc, ts = os.time() }
        status = "ok"
        fail_count = 0
        log.info("app_voc", string.format("采集成功：TVOC %d ppb (%.3f ppm)，等级 %d(%s)",
            ppb, ppm, level, desc))
        sys.publish("VOC_UPDATE", ppb, ppm, level, desc)
        return true
    end

    fail_count = fail_count + 1
    status = "read-error"
    log.warn("app_voc", "读取失败，连续失败", fail_count, "次")
    if fail_count % 10 == 0 then
        -- 攒够次数才补一条失败分类，避免每次都多占日志
        log.warn("app_voc", "连续失败分类（no-ack/no-data/crc）:", tostring(voc.last_error()))
    end
    sys.publish("VOC_ERROR", status, fail_count)
    return false
end

function M.open()
    local c = cfg()

    voc.close()
    if not voc.open(c.i2c_id) then
        status = "open-error"
        log.error("app_voc", "I2C 总线打开失败，i2c_id =", tostring(c.i2c_id))
        return false
    end

    if not voc.probe() then
        status = "not-found"
        local why = voc.last_error()
        if why == "no-ack" then
            log.warn("app_voc", "0x1A 写寄存器地址没 ACK → 查 VDD/GND/SCL/SDA 接线；"
                .. "AGS02MA 供电 3V3、电流约 28mA；总线速率超规格也会表现为无应答")
        elseif why == "no-data" then
            log.warn("app_voc", "0x1A 有 ACK 但数据读不回来 → I2C 时序问题：确认降速生效"
                .. "（config 的 hw.voc.i2c_delay，AGS02MA 要求 ≤30kHz）、SDA/SCL 上拉")
        elseif why == "crc" then
            log.warn("app_voc", "0x1A 数据读到了但 CRC 不过 → 总线太快 / 干扰："
                .. "把 hw.voc.i2c_delay 调大（20 → 30）再试")
        else
            log.warn("app_voc", "0x1A 探测失败，原因:", tostring(why))
        end
        return false
    end

    status = "ok"
    return true
end

function M.retry()
    voc.close()
    if M.open() then
        M.read_once()
        return true
    end
    log.warn("app_voc", "重新探测失败:", status)
    sys.publish("VOC_ERROR", status, fail_count)
    return false
end

-- 周期采集任务（start 首次成功、或后台重试成功后共用）
local function start_loop()
    local interval = M.interval()

    sys.taskInit(function()
        while true do
            M.read_once()
            sys.wait(interval)
        end
    end)

    log.info("app_voc", "TVOC 采集已启动，间隔", interval, "ms（刚上电有预热漂移属正常）")
end

function M.start()
    if M.open() then
        start_loop()
        return true
    end

    log.warn("app_voc", "空气质量传感器未就绪:", status, "→ 后台每 5 秒重试，最多 1 分钟")
    sys.publish("VOC_ERROR", status, 0)

    sys.taskInit(function()
        for i = 1, 12 do
            sys.wait(5000)
            if M.open() then
                log.info("app_voc", "重试第", i, "次成功，转入周期采集")
                start_loop()
                return
            end
        end
        log.error("app_voc", "重试 12 次仍不可用，请检查接线与总线速率（最后状态:", status, "）")
        sys.publish("VOC_ERROR", status, 0)
    end)

    return false
end

return M
