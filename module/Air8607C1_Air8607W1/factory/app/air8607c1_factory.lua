local cfg = require "air8607c1_config"
local board = require "air8607c1_board"
local baseboard = require "air8607c1_baseboard"
local w1 = require "air8607w1_factory"
local M = {}
local pc = rtos.bsp() == "PC"
local results, busy = {}, nil
local test_sequence = 0

function M.result(id)
    return results[id] or {state = "未测试", detail = ""}
end

local function report(id, state, detail)
    local result = {state = state, detail = detail or ""}
    results[id] = result
    log.info("factory", id, state, result.detail)
    sys.publish("C1_TEST_RESULT", id, result)
end

function M.is_busy()
    return busy ~= nil
end

function M.select_baseboard(name)
    if busy then return false, "请等待当前测试完成" end
    if baseboard.current().name == name then return true end
    local ok, reason = baseboard.save(name)
    if not ok then return false, reason end
    busy = "reboot"
    sys.timerStart(rtos.reboot, 300)
    return true
end

function M.wait_for_check(id, detail)
    report(id, pc and "待上板" or "待确认", detail)
end

function M.confirm(id, passed, detail)
    if M.result(id).state == "待确认" then
        report(id, passed and "通过" or "失败", detail or (passed and "现场确认通过" or "现场确认异常"))
    end
end

function M.fail(id, detail)
    if not pc then report(id, "失败", detail) end
end

function M.cancel(id)
    local state = M.result(id).state
    if state == "测试中" or state == "待确认" or state == "待连接" then
        report(id, "未测试", "已退出测试")
    end
end

local function now_us()
    local sec, us = mcu.ticks2(0)
    return sec * 1000000 + us
end

local function buzzer_test()
    local buzzer = cfg.buzzer
    local output = assert(gpio.setup(buzzer.pin, 0), "GPIO73 初始化失败")
    local half_period = math.floor(500000 / buzzer.hz + 0.5)
    local cycles = math.floor(buzzer.duration_ms * buzzer.hz / 1000)
    local ok, err = pcall(function()
        for _ = 1, cycles do
            for level = 1, 0, -1 do
                output(level)
                local deadline = now_us() + half_period
                repeat until now_us() >= deadline
            end
        end
    end)
    output(0)
    if not ok then return false, tostring(err) end
    return true, "BUZ1 已发出短音。听到声音后点「通过」。"
end

local function pwm_test()
    local p = cfg.pwm_test
    local ok, started = pcall(function()
        if not board.set_pwm1(p.duty) then return false end
        sys.wait(p.duration_ms)
        return true
    end)
    local closed, off = pcall(board.set_pwm1, 0)
    if not closed or not off then return false, "PWM1 未恢复到低电平" end
    if not ok or not started then return false, "PWM1 输出失败: " .. tostring(started) end
    return true, "请确认 J100-25 已测到 1 kHz、50% 占空比。"
end

-- Flash 与 TF 共用写入、关文件、重开读回、删除流程。
local function verify_file(p, label, filename)
    local path
    for _ = 1, 16 do
        test_sequence = test_sequence + 1
        local candidate = string.format(filename, p.mount_point, test_sequence)
        if not io.exists(candidate) then path = candidate; break end
    end
    if not path then return false, "无法创建新的 " .. label .. " 测试文件" end
    local parts = {}
    for i = 1, p.size // 4 do
        parts[i] = string.pack("<I4", (i * 2654435761 + test_sequence) & 0xFFFFFFFF)
    end
    local data = table.concat(parts)
    local file, created
    local ok, err = pcall(function()
        file = assert(io.open(path, "wb"))
        created = true
        assert(file:write(data), label .. " 写入失败")
        local closed = file:close()
        file = nil
        assert(closed, label .. " 写入提交失败")
        file = assert(io.open(path, "rb"))
        local readback = file:read(#data + 1)
        closed = file:close()
        file = nil
        assert(closed, label .. " 读取关闭失败")
        assert(readback == data, label .. " 读回数据不一致")
    end)
    if file then pcall(file.close, file) end
    if created and not os.remove(path) then return false, "无法删除测试文件 " .. path end
    if not ok then return false, tostring(err) end
    return true, string.format("%s %d KiB 写入、读回和删除通过", label, #data // 1024)
end

local function flash_test()
    for _, mount in pairs(io.lsmount()) do
        if mount.path == "" and mount.fs == "soc" then
            return verify_file(cfg.flash_test, "SPI Flash 根文件系统", "%s.air8607c1_flash_%08x.tmp")
        end
    end
    return false, "SPI Flash 根文件系统未挂载"
end

local actions = {
    buzzer = buzzer_test, flash = flash_test, pwm = pwm_test, dac = w1.dac_test,
    sd = function()
        return w1.sd_test(function()
            return verify_file(cfg.w1.sd, "SD/TF", "%s/C1%06X.TMP")
        end)
    end,
}

function M.run_job(id, message, action, success_state, session)
    if busy or not baseboard.supports(id) then return false end
    if pc then report(id, "待上板", "PC 预览不操作硬件"); return true end
    busy = id
    report(id, "测试中", message)
    sys.taskInit(function()
        local ok, passed, detail = pcall(action)
        busy = nil
        if session and session.closed then
            M.cancel(id)
        elseif not ok then
            report(id, "失败", tostring(passed))
        elseif not passed then
            report(id, "失败", detail)
        else
            report(id, success_state, detail)
        end
    end)
    return true
end

function M.run(id, session)
    local action = actions[id]
    if not action then return false end
    return M.run_job(id, id == "pwm" and "PWM1 正在输出，请在 J100-25 测量" or "正在执行",
        function()
            if session and session.closed then return false end
            return action(session)
        end, (id == "flash" or id == "sd") and "通过" or "待确认", session)
end

return M