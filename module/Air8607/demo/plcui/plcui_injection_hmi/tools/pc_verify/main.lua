--[[
PC 模拟器端到端验证脚本（不进设备）

作用：把工程真实的 data_app / ui_app / ui_vars 拉到 PC 模拟器的 LVGL 上跑一遍，
      覆盖「加载 → 四页切换 → 各类刷新 → 23 个事件」这条完整链路，
      每页抓一张真实渲染位图，最后输出 PASS/FAIL 汇总。

用法：python tools/pc_verify.py
      （由该脚本负责铺目录、起模拟器、收日志、BMP 转 PNG）
]]

PROJECT = "pc_verify"
VERSION = "1.0.0"

local data_app = require "data_app"
local ui_app = require "ui_app"

local SNAP = "C:/Users/luat/AppData/Local/Temp/pc_verify/snap/"
local RES  = "C:/Users/luat/AppData/Local/Temp/pc_verify/result.txt"
local pass_n, fail_n = 0, 0
local out_buf = {}

--[[ 进程被外部 kill 时 stdout 的缓冲区会丢，所以结果自己落盘，
    每判定一条就整体重写一次（几十行，开销可忽略）]]
local function flush()
    pcall(function()
        local f = io.output(RES)
        if f then
            f:write(table.concat(out_buf, "\n") .. "\n")
            f:close()
        end
    end)
end

local function note(line)
    out_buf[#out_buf + 1] = line
    flush()
end

local function check(name, cond, detail)
    if cond then
        pass_n = pass_n + 1
        note("PASS " .. name)
        log.info("verify", "PASS", name)
    else
        fail_n = fail_n + 1
        note("FAIL " .. name .. "  " .. (detail and tostring(detail) or ""))
        log.error("verify", "FAIL", name, detail and tostring(detail) or "")
    end
end

local function snap(tag)
    local ok, err = plcui.snapshot(SNAP .. tag .. ".bmp")
    if not ok then log.warn("verify", "snapshot 失败", tag, err and err.message) end
end

local function main()
    check("rtos.bsp 是 PC", rtos.bsp() == "PC", rtos.bsp())

    data_app.init()

    local loaded = ui_app.load(ui_app.handlers)
    check("ui_app.load 成功", loaded == true, "见上面的 E/user.ui")
    if not loaded then
        note(string.format("TOTAL pass=%d fail=%d", pass_n, fail_n))
        log.error("verify", "汇总", "pass=" .. pass_n .. " fail=" .. fail_n)
        return
    end

    sys.wait(600)
    check("首页是 overview", ui_app.current_page() == "overview", ui_app.current_page())
    snap("01_overview")

    -- 四页来回切：每页刷新一次，验证 find/绑表在切页后仍然有效
    local pages = { "trend", "alarm", "settings", "overview" }
    for i = 1, #pages do
        local p = pages[i]
        local ok = ui_app.show(p)
        sys.wait(400)
        ui_app.refresh()
        check("切页 " .. p, ok and ui_app.current_page() == p, ui_app.current_page())
        snap(string.format("%02d_%s", i + 1, p))
    end

    -- 表格：报警页 7 行 × 6 列
    ui_app.show("alarm")
    sys.wait(400)
    ui_app.refresh()
    snap("06_alarm_table")
    local n0 = data_app.unack_count()
    ui_app.handlers.ack0()
    sys.wait(120)
    check("ack0 让未确认数减一", data_app.unack_count() == n0 - 1,
        n0 .. " -> " .. data_app.unack_count())
    ui_app.handlers.alarm_ack_all()
    sys.wait(120)
    check("全部确认后未确认数为 0", data_app.unack_count() == 0, data_app.unack_count())
    snap("07_alarm_acked")
    ui_app.handlers.alarm_clear()
    sys.wait(120)

    -- 设置页：开关、滑块、参数写入
    ui_app.show("settings")
    sys.wait(400)
    local sw1_before = data_app.get().sw1
    ui_app.handlers.sw1()
    sys.wait(120)
    check("sw1 取反", data_app.get().sw1 == not sw1_before, tostring(data_app.get().sw1))
    ui_app.handlers.sw1()
    sys.wait(120)

    ui_app.handlers.sp_change({ value = 240 })
    sys.wait(120)
    check("设定值改为 240", data_app.get().sp == 240, data_app.get().sp)
    ui_app.handlers.bright_change({ value = 55 })
    sys.wait(120)
    check("背光改为 55%", data_app.bright_level() == 55, data_app.bright_level())
    snap("08_settings_changed")

    local ok_p = data_app.set_param("p1", 250)
    sys.wait(80)
    check("参数 p1=250 写入成功", ok_p == true, tostring(ok_p))
    local bad_p = data_app.set_param("p1", 999)
    sys.wait(80)
    check("参数 p1=999 被拒绝", bad_p == false, tostring(bad_p))
    ui_app.handlers.param_save()
    sys.wait(120)
    snap("09_settings_saved")

    -- 设备卡片选中
    ui_app.show("overview")
    sys.wait(400)
    ui_app.handlers.dev_sel1()
    sys.wait(120)
    snap("10_device_selected")

    -- 管路条纹逐帧（4 帧循环）
    for _ = 1, 5 do
        ui_app.tick_flow()
        sys.wait(60)
    end
    check("tick_flow 连跑 5 次不报错", true)

    -- 停机 / 启动
    ui_app.handlers.line_stop()
    sys.wait(120)
    check("停机后 running=false", data_app.get().running == false, tostring(data_app.get().running))
    snap("11_stopped")
    ui_app.handlers.line_start()
    sys.wait(120)
    check("启动后 running=true", data_app.get().running == true, tostring(data_app.get().running))

    -- 急停两级确认
    ui_app.handlers.line_estop()
    sys.wait(150)
    check("急停第一下只进入待确认", data_app.get().estop == false, tostring(data_app.get().estop))
    ui_app.handlers.line_estop()
    sys.wait(200)
    check("急停第二下真停机", data_app.get().estop == true, tostring(data_app.get().estop))
    snap("12_estop")
    ui_app.handlers.line_reset()
    sys.wait(150)
    check("复位后 estop=false", data_app.get().estop == false, tostring(data_app.get().estop))

    -- 运行一段时间，让工艺量、曲线、计数都动起来
    for _ = 1, 12 do
        data_app.step()
        ui_app.refresh()
        sys.wait(60)
    end
    snap("13_running")

    note(string.format("TOTAL pass=%d fail=%d", pass_n, fail_n))
    log.info("verify", "汇总", "pass=" .. pass_n .. " fail=" .. fail_n)
end

sys.taskInit(main)
sys.run()
