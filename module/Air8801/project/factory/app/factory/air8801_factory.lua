local cfg = require "air8801_config"
local M = {}
local results = {}
local running, sequence = nil, 0

function M.result(id)
    return results[id] or {state = "未测试", detail = ""}
end

function M.report(id, state, detail)
    results[id] = {state = state, detail = detail or ""}
    log.info("air8801_factory", id, state, detail)
    sys.publish("AIR8801_TEST_RESULT", id, results[id])
end

function M.busy()
    return running ~= nil
end

local function verify_file(prefix)
    local name
    repeat
        sequence = sequence + 1
        name = string.format("%s/A8%06X.TMP", prefix, sequence)
    until not io.exists(name)

    local parts = {}
    for i = 1, 2048 do parts[i] = string.pack("<I4", (2654435761 * i + sequence) & 0xFFFFFFFF) end
    local data = table.concat(parts)
    local file, created
    local ok, reason = pcall(function()
        file = assert(io.open(name, "wb"))
        created = true
        assert(file:write(data), "写入失败")
        local closed = file:close()
        file = nil
        assert(closed, "写入提交失败")
        file = assert(io.open(name, "rb"))
        local readback = file:read(#data + 1)
        closed = file:close()
        file = nil
        assert(closed and readback == data, "读回校验失败")
    end)
    if file then pcall(file.close, file) end
    if created and not os.remove(name) then return false, "无法删除本轮测试文件" end
    return ok, ok and "8192 字节写入、读回校验及清理完成" or tostring(reason)
end

local function flash_test()
    for _, mount in pairs(io.lsmount()) do
        if mount.path == "" and mount.fs == "soc" then return verify_file("") end
    end
    return false, "SPI6 根文件系统未挂载"
end

local function sd_test()
    local sd = cfg.sd
    local powered, opened, mounted
    local ok, passed, detail = pcall(function()
        powered = assert(gpio.setup(sd.power, 0), "SD_EN")
        assert(gpio.setup(sd.cs, 1), "SPI1 CS")
        powered(1)
        sys.wait(100)
        assert(spi.setup(sd.id, 255, 0, 0, 8, 400000) == 0, "SPI1 初始化失败")
        opened = true
        local ready, reason = fatfs.mount(fatfs.SPI, sd.mount, sd.id, sd.cs, sd.hz, nil, 1, false)
        assert(ready, "J100 挂载失败，请检查 FAT 格式 TF 卡。错误 " .. tostring(reason))
        mounted = true
        return verify_file(sd.mount)
    end)
    local unmounted, code = true, 0
    if mounted then unmounted, code = pcall(fatfs.unmount, sd.mount) end
    local closed = not opened or pcall(spi.close, sd.id)
    if powered then powered(0) end
    if not unmounted or code ~= 0 then return false, "TF 卸载失败 " .. tostring(code) end
    if not closed then return false, "SPI1 关闭失败" end
    if not ok then return false, tostring(passed) end
    return passed, detail
end

local function buzzer_test()
    local b = cfg.buzzer
    local ok, reason = pcall(function()
        assert(pwm.open(b.channel, b.hz, 50), "PWM1 启动失败")
        sys.wait(b.duration_ms)
    end)
    pcall(pwm.close, b.channel)
    assert(gpio.setup(b.pin, 0), "蜂鸣器空闲电平恢复失败")
    return ok, ok and "听到 D120 短音后点通过" or tostring(reason)
end

--[[串口回传测试（电脑回环）：UART2（TX GPIO54 / RX GPIO55，9600 8N1）。

一轮就三件事：设备先发 3 个字节 A8K → 人/上位机把这 3 个字节发回来 → 10 秒内收到一致的 3 字节即通过。
不需要短接 TX/RX 的工装，也不需要上位机解析协议：串口助手手动发回、或自动回显脚本都行。
发出后只提示一次「已发 A8K，请在 10 s 内回传」，然后静默等满 10 s：串口线上一帧，日志只有两行。

通道由型号的电平段决定（K8801_TTL_… / K8801_232_…，落到 cfg.serial.mode），判定完全相同，差别只在 RS232_3V3（GPIO12）：
- ttl  ：GPIO12 保持低，J101-2/3 接 3.3V TTL（USB-TTL 小板），信号参考地 J101-4；
- rs232：GPIO12 拉高给收发器供电，J101 经 RS232 电平接到电脑串口（或 USB-RS232）。

判定用「3 字节是否出现在回传数据里」，容忍上位机前后多打的字符（回车、提示符等）。]]
local SERIAL_PROBE = "A8K"
local SERIAL_WAIT_MS, SERIAL_POLL_MS = 10000, 20

-- 硬件只有一条串口支路实贴，通道由型号的电平段（TTL/232）决定（cfg.serial.mode）。
-- 界面上永远只有一项，结果表键统一用 SERIAL_ID，切换通道不影响其它测试项。
local SERIAL_ID = "serial"
local serial_modes = {
    ttl = {label = "TTL", rs232 = false, menu = "TTL 串口",
        desc = "J101-2/3 · 发 A8K 等电脑回传 10s", hint = "J101-2/3 接 USB-TTL 再把 A8K 发回"},
    rs232 = {label = "RS232", rs232 = true, menu = "RS232 串口",
        desc = "J101 · 发 A8K 等电脑回传 10s", hint = "J101 接 RS232 再把 A8K 发回（收发器须实贴）"},
}

local function serial_echo_test()
    local s = cfg.serial
    local m = serial_modes[s.mode] or serial_modes.ttl
    local rx, powered, opened, got = "", nil, false, 0
    local ok, passed, detail = pcall(function()
        powered = assert(gpio.setup(s.power, 0), "RS232_3V3")
        powered(m.rs232 and 1 or 0)  -- TTL 测试期间收发器必须断电，避免它驱动 J101
        if m.rs232 then sys.wait(80) end  -- 等收发器上电稳定再开串口
        assert(uart.setup(s.id, s.baud, 8, 1, uart.NONE) == 0, "UART" .. s.id .. " 初始化失败")
        opened = true
        uart.on(s.id, "receive", function(_, len)
            local data = uart.read(s.id, len)
            if data and #data > 0 then rx = rx .. data end
        end)
        uart.rxClear(s.id)  -- 丢弃上电噪声与历史残留
        assert((uart.write(s.id, SERIAL_PROBE) or -1) >= 0, "发送失败")
        log.info("air8801_factory", "串口已发", m.label, SERIAL_PROBE,
            string.format("等上位机回传 %ds", SERIAL_WAIT_MS // 1000))
        -- 只提示一次，等待期间不再刷新：串口只发一帧，日志只有「已发」和「结果」两行
        M.report(SERIAL_ID, "测试中", string.format("已发 %s，请在 %d s 内回传",
            SERIAL_PROBE, SERIAL_WAIT_MS // 1000))
        local waited = 0
        while waited < SERIAL_WAIT_MS do
            sys.wait(SERIAL_POLL_MS)
            waited = waited + SERIAL_POLL_MS
            if rx:find(SERIAL_PROBE, 1, true) then
                return true, string.format("%s 已回传 %s（%d.%d s，9600 8N1）",
                    m.label, SERIAL_PROBE, waited // 1000, (waited % 1000) // 100)
            end
        end
        got = #rx
        if got == 0 then
            return false, string.format("%ds 未收到回传：%s", SERIAL_WAIT_MS // 1000, m.hint)
        end
        return false, string.format("收到 %d 字节但不是 %s：查大小写、波特率与校验位", got, SERIAL_PROBE)
    end)
    if opened then
        pcall(uart.on, s.id, "receive", nil)
        pcall(uart.close, s.id)
    end
    if powered then powered(0) end
    if not ok then return false, tostring(passed) end
    return passed, detail
end

--- 功能测试页用的串口项：只返回一项，名称与描述随型号电平段（TTL/232）变化
function M.serial_info()
    local m = serial_modes[cfg.serial.mode] or serial_modes.ttl
    return {id = SERIAL_ID, name = m.menu, icon = "other_func", desc = m.desc, action = "发 3 字节"}
end

local actions = {
    flash = flash_test,
    sd = sd_test,
    buzzer = buzzer_test,
    [SERIAL_ID] = serial_echo_test,
}

function M.run(id)
    local test = actions[id]
    if running or not test then return false end
    if _G.is_pc then M.report(id, "待上板", "请在 Air8801 实板运行"); return true end
    running = id
    M.report(id, "测试中")
    sys.taskInit(function()
        local ok, passed, detail = pcall(test)
        running = nil
        if ok and passed then
            M.report(id, id == "buzzer" and "待确认" or "通过", detail)
        else
            M.report(id, "失败", tostring(ok and detail or passed))
        end
    end)
    return true
end

return M
