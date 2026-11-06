--[[
@module  udisk
@summary U盘（USB HOST / MSC）枚举与fatfs挂载
@version 1.0
@date    2026.11.06
@author  黄何
@usage
硬件（Air8603 原理图 P4）：
    J14 = USB-A母座（1 VBUS +5.5V / 2 D- / 3 D+ / 4 GND），U盘插这里
    J7  = 4pin USB端子（与J14做兼容设计，同一组D+/D-）
    注意：J14的+5.5V不是直供，而是由U0022(JW5357S)产生，EN接UVC_EN；
          UVC_EN在Air8603上是PIN58(GPIO58)，所以本模块默认会把GPIO58拉高。

软件流程（LuatOS官方口径）：
    pm.power(pm.USB,false) → usb.mode(0, usb.HOST) → usb.on(0, cb) → pm.power(pm.USB,true)
    ↑ 必须先掉电再切模式，且回调要在上电前注册，否则第一个接入事件会漏掉

    枚举到U盘：class == usb.MSC 且 event == usb.EV_CONNECT
        → 回调给出app_id → fatfs.mount(fatfs.USB, "/udisk", app_id)
    拔出：event == usb.EV_DISCONNECT → fatfs.unmount("/udisk")

★ 切到HOST模式后，Type-C那个USB串口日志可能会消失（同一路USB控制器），
  看日志请走J10的UART，或者看应用写到SD卡里的日志文件。
]]

local M = {}

local CFG = {
    mount    = "/udisk",
    usb_id   = 0,
    -- J14的+5.5V使能脚：Air8603上是UVC_EN=PIN58(GPIO58)
    -- 如果本机硬件把PIN58贴成了485_EN2，拉高只是让485-2使能，对U盘没有影响
    pwr_pin  = 58,
    mount_retry = 3,     -- 挂载重试次数（个别U盘枚举后要等几十ms才可读）
}

local mounted      = false
local ever_mounted = false   -- 是否曾经成功挂上过（用来区分"真拔出"和"枚举失败"）
local app_id       = nil
local state        = "idle"  -- idle / waiting / mounted / removed
local pending      = false   -- 回调里收到"已接入"，等主任务去挂载
local enum_fails   = 0       -- 枚举失败次数（C层MSC放弃会直接发DISCONNECT）
local last_err

function M.is_mounted() return mounted end
function M.had_mounted() return ever_mounted end
function M.enum_fails() return enum_fails end
function M.state() return state end
function M.mount_point() return CFG.mount end
function M.last_err() return last_err end

-- ==================== 挂载 / 卸载 ====================
local function do_mount()
    if mounted or type(app_id) ~= "number" then return false end
    if not (fatfs and fatfs.mount and fatfs.USB) then
        last_err = "固件未包含fatfs.USB（需要带USB HOST的固件）"
        log.error("udisk", last_err)
        return false
    end

    for i = 1, CFG.mount_retry do
        local ok, err = pcall(fatfs.mount, fatfs.USB, CFG.mount, app_id)
        if ok and err ~= false then
            -- 注意：这里不传auto_format，U盘里是用户的数据，绝对不能格式化
            mounted, ever_mounted, state = true, true, "mounted"
            local t = nil
            pcall(function() local d = fatfs.getfree(CFG.mount) if type(d) == "table" then t = d end end)
            log.info("udisk", string.format("U盘挂载成功 %s（app_id=%d）%s", CFG.mount, app_id,
                t and string.format("总 %s KB / 剩 %s KB", tostring(t.total_kb), tostring(t.free_kb)) or ""))
            sys.publish("UDISK_MOUNTED")
            return true
        end
        last_err = tostring(err)
        log.warn("udisk", string.format("U盘挂载第 %d/%d 次失败：%s（等300ms重试）",
            i, CFG.mount_retry, last_err))
        sys.wait(300)
    end

    state = "waiting"
    log.error("udisk", "U盘挂载失败：" .. tostring(last_err)
        .. " —— 查：是否FAT32单分区 / 供电 / D+ D- 是否接反")
    return false
end

-- @param silent boolean true=程序主动卸载，不广播"拔出"事件（避免误报中止）
function M.unmount(silent)
    if not mounted then return true end
    pcall(fatfs.unmount, CFG.mount)
    mounted, state = false, silent and "idle" or "removed"
    log.info("udisk", "U盘已卸载 " .. CFG.mount .. "（可以安全拔出）")
    if not silent then sys.publish("UDISK_REMOVED") end
    return true
end

-- ==================== USB 回调 ====================
local function on_usb(usb_id, class, id, event, p1, p2, p3)
    -- 形参依次是 usb_id, class, app_id, event, param1..3
    if class ~= usb.MSC then
        -- 摄像头/键鼠/网卡插进来也会走这里，不属于本应用关注的范围
        if event == usb.EV_CONNECT then
            log.info("udisk", string.format("忽略非存储设备 class=%s app_id=%s", tostring(class), tostring(id)))
        end
        return
    end

    if event == usb.EV_CONNECT then
        app_id, pending, state = id, true, "waiting"
        log.info("udisk", string.format("检测到U盘：app_id=%d hub=%s port=%s addr=%s",
            id, tostring(p1), tostring(p2), tostring(p3)))
        sys.publish("UDISK_EV")

    elseif event == usb.EV_DISCONNECT then
        local was = mounted
        mounted, pending, app_id, state = false, false, nil, was and "removed" or "waiting"
        pcall(fatfs.unmount, CFG.mount)

        if was or ever_mounted then
            -- 真拔出：正在传输的文件要停下来
            log.warn("udisk", "U盘已拔出（app_id=" .. tostring(id) .. "）")
            sys.publish("UDISK_REMOVED")
        else
            -- 还没挂上就断开 = C层MSC枚举/握手失败，不是"拔出"，
            -- 不能因此中止整个应用（否则换个盘插上去也没机会重试）
            enum_fails = enum_fails + 1
            log.warn("udisk", string.format(
                "U盘枚举失败（第%d次，app_id=%s）：MSC握手未通过，常见于多合一读卡器/空卡槽/供电不足",
                enum_fails, tostring(id)))
        end
        sys.publish("UDISK_EV")

    else
        log.info("udisk", string.format("USB事件 event=%s class=%s app_id=%s",
            tostring(event), tostring(class), tostring(id)))
    end
end

-- ==================== 启动 ====================
function M.start()
    if not usb then
        last_err = "固件未包含usb库（需要Air1601/Air1603 V1024+且编译了USB HOST）"
        log.error("udisk", last_err)
        return false, last_err
    end
    if not usb.MSC or not usb.HOST then
        last_err = "usb库缺少HOST/MSC定义，固件不支持USB主机模式"
        log.error("udisk", last_err)
        return false, last_err
    end

    -- USB口供电（可选）
    if CFG.pwr_pin then
        pcall(gpio.setup, CFG.pwr_pin, 0)
        pcall(gpio.set, CFG.pwr_pin, 1)
        sys.wait(100)
        log.info("udisk", "USB口供电脚 GPIO" .. CFG.pwr_pin .. " 已拉高")
    end

    -- 1、先让USB掉电，再切主机模式（顺序不能反）
    if pm and pm.power and pm.USB then
        pcall(pm.power, pm.USB, false)
        sys.wait(50)
    end
    -- 注意：usb.mode / usb.on 在USB带电时会直接返回false（不报错），
    --       所以不能只看pcall的成败，必须同时判返回值
    local call_ok, ret = pcall(usb.mode, CFG.usb_id, usb.HOST)
    if not call_ok or ret == false then
        last_err = "usb.mode(HOST)失败：" .. tostring(ret) .. "（USB必须先掉电）"
        log.error("udisk", last_err)
        return false, last_err
    end

    -- 2、回调必须在"上电前"注册
    local ok_on, ret_on = pcall(usb.on, CFG.usb_id, on_usb)
    if not ok_on or ret_on == false then
        last_err = "usb.on注册失败：" .. tostring(ret_on)
        log.error("udisk", last_err)
        return false, last_err
    end

    -- 3、上电，开始枚举
    if pm and pm.power and pm.USB then
        pcall(pm.power, pm.USB, true)
    end
    state = "waiting"
    log.info("udisk", "USB已切到HOST模式，等待U盘接入…")

    -- 4、后台任务：把"回调收到的接入"落实成挂载（不在USB回调里做文件系统操作）
    sys.taskInit(function()
        while true do
            if pending and not mounted then
                pending = false
                do_mount()
            end
            sys.waitUntil("UDISK_EV", 1000)
        end
    end)
    return true
end

-- 等U盘挂上（带超时），返回boolean
function M.wait_mounted(timeout_ms)
    local waited = 0
    while waited < (timeout_ms or 30000) do
        if mounted then return true end
        if pending then
            pending = false
            do_mount()
            if mounted then return true end
        end
        sys.waitUntil("UDISK_MOUNTED", 1000)
        waited = waited + 1000
    end
    return mounted
end

return M
