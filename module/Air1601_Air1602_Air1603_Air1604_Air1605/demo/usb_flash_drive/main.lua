--[[
@module  main
@summary LuatOS用户应用脚本文件入口,总体调度应用逻辑
@version 1.0
@date    2026.11.4
@author  晁丹
@usage

本demo演示的功能为：
-- Air860x U 盘测试：识别模块 -> 打开对应 VBUS 脚 -> 挂载 /udisk -> 循环 读(列文件名) / 写(读回比对)
-- 目前该demo适配Air8601_V1.0 WIFI/4G,Air8603,Air8605
]]

--[[
必须定义PROJECT和VERSION变量,Luatools工具会用到这两个变量,远程升级功能也会用到这两个变量
PROJECT：项目名,ascii string类型
        可以随便定义,只要不使用,就行
VERSION：项目版本号,ascii string类型
        如果使用合宙iot.openluat.com进行远程升级,必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字,三个X表示的数字可以相同,也可以不同,同理三个Y和三个Z表示的数字也是可以相同,可以不同
            因为历史原因,YYY这三位数字必须存在,但是没有任何用处,可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级,根据自己项目的需求,自定义格式即可
]]


PROJECT = "AIR860X_UDISK"
VERSION = "001.000.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)



-- 脚本层是否被加载的唯一证据：看不到这行说明脚本没执行，与下面逻辑无关
log.info("U盘", "脚本已加载", rtos and rtos.bsp() or "?")

local MOUNT = "/udisk"
local FILE = "/udisk/udisk_test.txt"

-- 掉线只信 USB 事件：fatfs 不会自己感知设备没了，断开后 io.lsdir 仍返回 true + 空表
local M = {
    round = 0,
    mounted = false,
    unplugged = false,
    app = nil,
    fail = 0
}

-- pin = U 盘 VBUS 使能脚；extra = 命中后补拉的共轨脚
-- 顺序即探测顺序，同主控时按表序试脚
local BOARDS = {{
    id = "Air8601",
    name = "Air8601",
    chips = {"Air1601"},
    pin = 73,
    extra = {}
}, {
    id = "Air8605",
    name = "Air8605/8605B",
    chips = {"Air1601", "Air1602"},
    pin = 58,
    extra = {12}
}, {
    id = "Air8603",
    name = "Air8603",
    chips = {"Air1603"},
    pin = 58,
    extra = {},
    share = true
}}

local function chip()
    local ok, m = pcall(function()
        return hmeta and hmeta.model()
    end)
    if ok and type(m) == "string" and m ~= "" then
        return m
    end
    ok, m = pcall(function()
        return rtos and rtos.bsp()
    end)
    if ok and type(m) == "string" then
        return m
    end
    return "unknown"
end

local function on_usb(usb_id, class, app_id, event)
    if event == usb.EV_CONNECT then
        if class == usb.MSC then
            M.app = app_id or 0
            M.unplugged = false
        end
    elseif event == usb.EV_DISCONNECT then
        -- 本工程只接 U 盘，任何设备断开都按 U 盘掉了处理
        M.unplugged = true
        M.app = nil
    end
    -- 只做唤醒，真相是上面的标志位
    sys.publish("USB_EVT")
end

local function cfg_str(b)
    if #b.extra == 0 then
        return string.format("VBUS GPIO%d", b.pin)
    end
    local t = {}
    for _, p in ipairs(b.extra) do
        t[#t + 1] = tostring(p)
    end
    return string.format("VBUS GPIO%d + 共轨 GPIO%s", b.pin, table.concat(t, "/"))
end

-- 每个脚整机只驱动一次，且用 gpio.setup(pin, 1) 一次到位。
local pulled = {}

local function pull(pin)
    if pulled[pin] then
        return
    end
    pulled[pin] = true
    gpio.setup(pin, 1)
end

-- 探测阶段只拉 b.pin：extra 可能正是别的板型的 VBUS 脚，一起拉会让判定错
local function power(b, with_extra)
    if with_extra then
        for _, p in ipairs(b.extra) do
            pull(p)
        end
    end
    pull(b.pin)
end

local usb_ready = false

-- USB 主机只初始化一次。反复 usb.mode + 上下电会让第二次枚举失效
local function usb_host_once()
    if usb_ready then
        return true
    end
    for i = 1, 3 do
        pcall(pm.power, pm.USB, false)
        -- 掉电不足时 usb.mode 会返回 true 却不生效；从机 CDC 残留会一直刷 no hub port
        sys.wait(200)
        pcall(usb.clear_all_class, 0)
        local ok = usb.mode(0, usb.HOST)
        -- 回调必须早于上电，否则漏掉第一个设备的接入事件
        usb.on(0, on_usb)
        sys.wait(100)
        pcall(pm.power, pm.USB, true)
        sys.wait(200)
        if ok then
            usb_ready = true
            return true
        end
        log.warn("U盘", string.format("usb.mode 切 HOST 失败，第 %d 次重试", i))
        sys.wait(500)
    end
    log.error("U盘", "USB 主机模式起不来")
    return false
end

-- 等 U 盘接入：靠标志位轮询，不靠消息
local function wait_in(ms)
    local left = ms
    while left > 0 do
        if M.app ~= nil and not M.unplugged then
            return true
        end
        sys.wait(100)
        left = left - 100
    end
    return M.app ~= nil and not M.unplugged
end

-- 试一个板型：只切 GPIO，不碰 USB 栈
local function try_board(b)
    M.app = nil
    M.unplugged = false
    power(b, false)
    if wait_in(2500) then
        power(b, true)
        return true
    end
    -- 不拉低：8605 板上 GPIO73 是另一路电源使能，拉低会把 U 盘那路一起关掉
    sys.wait(300)
    return false
end

-- 先看主控筛掉不可能的几个，再逐个开供电试，谁能枚举出 U 盘就是谁
local function detect(c)
    local list = {}
    for _, b in ipairs(BOARDS) do
        for _, x in ipairs(b.chips) do
            if c == x or c:find(x, 1, true) or x:find(c, 1, true) then
                list[#list + 1] = b
                break
            end
        end
    end
    if #list == 0 then
        list = BOARDS
    end

    local names = {}
    for _, b in ipairs(list) do
        names[#names + 1] = b.id
    end
    log.info("U盘", string.format("主控: %s | 候选: %s", c, table.concat(names, " / ")))

    if not usb_host_once() then
        return list[1], false
    end

    for _, b in ipairs(list) do
        if try_board(b) then
            log.info("U盘", string.format("探测: GPIO%d 命中 %s（app_id=%s）", b.pin, b.name, tostring(M.app)))
            return b, true
        end
        log.info("U盘", string.format("探测: GPIO%d 无接入（%s）", b.pin, b.name))
    end

    -- 一个都没枚举出来，多半是还没插盘：按最可能的模块先供着电，插上再认
    log.warn("U盘", "所有接口都没枚举出 U 盘")
    power(list[1], true)
    return list[1], false
end

local function mount(app, quiet)
    -- 第 8 参 auto_format 必须 false，默认 true 会在挂载失败时把盘格式化
    local ok, ret, err = pcall(fatfs.mount, fatfs.USB, MOUNT, app or 0, nil, nil, nil, nil, false)
    if not ok then
        log.error("U盘", "挂载异常:", tostring(ret))
        return false
    end
    if ret ~= true then
        -- 枚举还没走完就挂载只会拿到 NOTRDY，属于可重试
        if quiet then
            log.warn("U盘", "挂载未就绪，重试:", tostring(err))
        else
            log.error("U盘", "挂载失败:", tostring(err))
        end
        return false
    end
    M.mounted = true
    log.info("U盘", "挂载成功 " .. MOUNT)
    return true
end

local function unmount()
    if not M.mounted then
        return
    end
    pcall(fatfs.unmount, MOUNT)
    M.mounted = false
end

local function list_files()
    -- io.lsdir 返回两个值，pcall 必须接三个
    local ok, ret, data = pcall(io.lsdir, MOUNT, 100, 0)
    if not ok or not ret or type(data) ~= "table" then
        log.error("U盘", "读: 列目录失败")
        return false
    end
    -- 掉线后 opendir 仍成功、readdir 读不到东西，返回的是 true + 空表，不能算成功
    if #data == 0 then
        log.error("U盘", "读: 0 项（设备已掉线或空盘）")
        return false
    end
    log.info("U盘", string.format("读: 共 %d 项", #data))
    for i, e in ipairs(data) do
        log.info("U盘", string.format("  [%02d] %-4s %8d  %s", i, e.type == 1 and "DIR" or "FILE", e.size or 0,
            tostring(e.name)))
    end
    return true
end

local function write_file()
    local txt = string.format("AIR860X 第%d轮 %s\r\n", M.round, os.date("%Y-%m-%d %H:%M:%S"))

    local f, err = io.open(FILE, "wb")
    if not f then
        log.error("U盘", "写: 打开失败", tostring(err))
        return false
    end
    local wok = f:write(txt)
    -- 不 close 不会刷到 U 盘
    f:close()
    if not wok then
        log.error("U盘", "写: 写入失败")
        return false
    end

    local rf = io.open(FILE, "rb")
    local back = rf and rf:read("*a")
    if rf then
        rf:close()
    end
    if back ~= txt then
        log.error("U盘", "写: 读回不一致")
        return false
    end

    log.info("U盘", "写: 成功  " .. string.gsub(txt, "[\r\n]", ""))
    return true
end

sys.taskInit(function()
    sys.wait(500)

    if not usb or not fatfs or fatfs.USB == nil then
        log.error("U盘", "固件缺 usb 库或 fatfs.USB")
        return
    end

    local b, verified
    local retry_left = 3

    -- 只做一次：命中哪个模块就用哪个，之后整段循环只按这个配置读写
    local function scan()
        b, verified = detect(chip())
        log.info("U盘",
            string.format("模块: %s | %s", b.name, verified and "接口检出" or "未插盘，按主控推测"))
        log.info("U盘", "配置: " .. cfg_str(b))
    end

    scan()

    while true do
        if not usb_ready and not usb_host_once() then
            sys.wait(2000)
        end

        if M.unplugged then
            if M.mounted then
                log.warn("U盘", "设备已断开，卸载")
                unmount()
            end
            M.fail = 0
        end

        if not M.mounted then
            if M.app ~= nil then
                local app = M.app
                -- 枚举到 MSC 就绪要 200~400ms，第一枪给足时间，之后每 400ms 重试
                for i = 1, 5 do
                    sys.wait(i == 1 and 500 or 400)
                    if M.app ~= app then
                        break -- 期间掉了或换了设备，别对着旧 app_id 硬挂
                    end
                    if mount(app, i > 1) then
                        break
                    end
                end
                if not M.mounted and M.app == app then
                    log.warn("U盘", "挂载 5 次仍失败，等重新插入")
                    M.app = nil
                end
            else
                if not sys.waitUntil("USB_EVT", 10000) and not verified and retry_left > 0 then
                    retry_left = retry_left - 1
                    log.info("U盘", string.format("还没插盘，重探一轮（还可重探 %d 次）", retry_left))
                    scan()
                end
            end
        else
            M.round = M.round + 1
            local r = list_files()
            -- 读失败也照写：空盘第一次本来就没有条目，写成功说明设备还活着
            local w = write_file()
            log.info("U盘", string.format("[第 %d 轮] 读 %s / 写 %s", M.round, r and "成功" or "失败",
                w and "成功" or "失败"))
            if r and w then
                M.fail = 0
                sys.wait(1000)
            else
                M.fail = M.fail + 1
                if M.fail >= 2 then
                    log.warn("U盘", "读写连续失败，卸载等重插")
                    unmount()
                    M.fail = 0
                else
                    sys.wait(500)
                end
            end
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

