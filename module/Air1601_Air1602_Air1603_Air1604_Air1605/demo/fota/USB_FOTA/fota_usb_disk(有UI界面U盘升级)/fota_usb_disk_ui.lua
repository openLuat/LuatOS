--[[
@module  fota_usb_disk_ui
@summary U盘FOTA升级业务核心（有UI界面版）—— 切HOST/挂载/列举/等待确认/fota写入/校验/重启
@version 1.0
@date    2026.11.11
@author  谌程
@usage
-- 由无UI版 fota_usb_disk.lua 改造而来，fota 写入链路(步骤5~8)一行未改，主要差异：
-- 1. 删除"开机5秒自动触发"：开机即进入HOST主机模式并常驻；先检查U盘是否已插入
--    (兼容开机前已插好)，未插入才等枚举事件；挂载后列目录发 UDISK_LIST，
--    UI是仿电脑资源管理器的文件夹浏览器(可逐级进目录), 只有*.bin可选中为升级包；
--    用户点右上角✕关闭选择页，unmount后重新插拔U盘可再次进入；
-- 2. 升级包路径不再固定 update.bin，由用户在UI上选择后经 FOTA_UPGRADE_START(path) 传入；
-- 3. 写入过程按进度发 FOTA_PROGRESS(done,total,text)（按1%节流，避免刷UI太频繁）；
-- 4. 失败后不再切回从机模式（切回去就再也检测不到U盘），
--    只 unmount + 重新挂载扫描，用户可直接换包重试，无需重新上电。
--
-- 事件约定（与 ui.lua 对接）：
--   发布 UDISK_LIST(dir,items) / UDISK_REMOVED / FOTA_PROGRESS(done,total,text) / FOTA_RESULT(ok,msg)
--   发布 UDISK_RESCAN 由UI"刷新"按钮触发（本模块订阅）
--   订阅 FOTA_UPGRADE_START(path) 由UI二次确认后触发（本模块订阅）
--
-- 升级包制作方法、U盘要求(FAT32/勿用读卡器)等见同目录 readme.md
]]

local conf   = require "conf"
local lcd_tp = require "lcd_tp"   -- 显示+触摸初始化(下面的自启动流程要用)
local ui     = require "ui"       -- 界面构建(下面的自启动流程要用)
local U      = conf.usb

-- 模块对外接口表(末尾 M.start/return M 依赖它, 缺了会报 "attempt to index a nil value (global 'M')")
local M = {}

local MOUNT_POINT = U.mount
local USB_ID      = U.id
local USB_PWR_PIN = U.pwr_pin
local SUFFIX      = U.suffix
local MAX_FILES   = U.max_files
local READ_BLOCK  = U.block

-- 全局状态
local msc_connected = false    -- U盘(MSC)是否已枚举连接
local disk_mounted  = false    -- U盘是否已挂载
local usb_app_id    = nil      -- 枚举成功后底层分配的app_id, 挂载必须用它
local user_start    = false    -- 用户是否已确认升级
local user_path     = nil      -- 用户选择的升级包完整路径
local close_req     = false    -- 用户点✕请求关闭选择页(主任务循环里处理unmount)

-- ==================== USB事件回调 ====================
local function usb_event_cb(id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT and class == usb.MSC then
        log.info("FOTA_USB_UI", "检测到U盘插入", "app_id", app_id)
        usb_app_id = app_id
        msc_connected = true
        sys.publish("USB_MSC_CONNECT")
    elseif event == usb.EV_DISCONNECT and class == usb.MSC then
        log.warn("FOTA_USB_UI", "U盘已拔出")
        msc_connected = false
        usb_app_id = nil
        if disk_mounted then
            pcall(fatfs.unmount, MOUNT_POINT)
            disk_mounted = false
            sys.publish("UDISK_REMOVED")
        end
    end
end

usb.on(USB_ID, usb_event_cb)

-- ==================== 内部工具 ====================

-- 进度上报: 写UI日志并发布(节流由调用方控制)
local function report_progress(done, total, text)
    sys.publish("FOTA_PROGRESS", done, total, text)
end

-- 开机进入HOST主机模式并常驻(必须在USB外设掉电状态下设置模式)
local function enter_host_mode()
    if USB_PWR_PIN then
        pcall(gpio.setup, USB_PWR_PIN, 0)
        pcall(gpio.set, USB_PWR_PIN, 1)
        sys.wait(100)
        log.info("FOTA_USB_UI", "U盘供电脚GPIO" .. USB_PWR_PIN .. " 已拉高")
    end
    pm.power(pm.USB, false)
    local mode_ok = usb.mode(USB_ID, usb.HOST)
    pm.power(pm.USB, true)
    if not mode_ok then
        log.error("FOTA_USB_UI", "USB切换主机模式失败")
        return false
    end
    log.info("FOTA_USB_UI", "USB已进入HOST主机模式, 等待U盘插入...")
    return true
end

-- 挂载U盘(使用回调返回的app_id, 3次重试: 个别U盘枚举完成后需等待才可读)
local function mount_udisk()
    sys.wait(500) -- 枚举完成后稍作等待, 让底层稳定
    for i = 1, 3 do
        if fatfs.mount(fatfs.USB, MOUNT_POINT, usb_app_id) then
            disk_mounted = true
            log.info("FOTA_USB_UI", "U盘挂载成功: ", MOUNT_POINT)
            return true
        end
        log.warn("FOTA_USB_UI", "U盘挂载第", i, "/3次失败, 300ms后重试")
        sys.wait(300)
    end
    log.error("FOTA_USB_UI", "U盘挂载失败, 请确认U盘为FAT32格式")
    return false
end

-- 列目录全部内容(仿电脑资源管理器): 文件夹+文件都列出, UI负责"只有*.bin可选"
-- io.lsdir 的两种前缀写法都试一次(luadb与fatfs的挂载前缀写法不同, 见sd_app.lua)
-- 返回 items 表: {name,path,size,is_dir}, 文件夹在前、同类型按名称排序; 失败返回nil,err
local function list_dir_items(dir)
    local list = {}
    local data = nil
    local err = "目录为空或列举失败"
    local candidates = { dir .. "/", dir }
    for i = 1, #candidates do
        local ret, list_data = io.lsdir(candidates[i], 200, 0)
        if ret and type(list_data) == "table" then
            data = list_data
            break
        end
    end
    if not data then
        log.warn("FOTA_USB_UI", "目录列举失败", dir)
        return nil, err
    end

    for i = 1, #data do
        local item = data[i]
        local raw = tostring(item.name or "")
        local name = raw:match("([^/\\]+)$") or raw
        if #name > 0 and name ~= "." and name ~= ".." then
            local is_dir = (item.type ~= 0)  -- type==0 是普通文件, 其余按文件夹处理
            local path = dir .. "/" .. name
            local size = 0
            if not is_dir then
                if not io.exists(path) and io.exists(raw) then
                    path = raw  -- 个别固件lsdir返回的名字带挂载前缀, 兜底
                end
                size = io.fileSize(path) or item.size or 0
            end
            list[#list + 1] = { name = name, path = path, size = size, is_dir = is_dir }
        end
    end

    -- 排序: 文件夹在前, 同类型按名称
    table.sort(list, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)
    log.info("FOTA_USB_UI", "列目录", dir, "文件夹/文件", #list)
    return list
end

-- 列目录并发布给UI(供"挂载成功/进入文件夹/返回上一级"复用)
local function publish_dir(dir)
    local items, err = list_dir_items(dir)
    if not items then
        sys.publish("FOTA_RESULT", false, "目录读取失败:\n" .. tostring(dir) .. "\n" .. tostring(err))
        return false
    end
    sys.publish("UDISK_LIST", dir, items)
    return true
end

-- 挂载+从根目录开始浏览(供"插入U盘"和"失败重试"和"手动刷新"三条路径复用)
local function mount_and_report()
    if not msc_connected or not usb_app_id then
        return false
    end
    if not mount_udisk() then
        sys.publish("FOTA_RESULT", false, "U盘挂载失败\n请确认U盘为FAT32单分区格式\n拔出重新插入可重试")
        return false
    end
    return publish_dir(MOUNT_POINT)
end

-- ==================== 升级流程 ====================
-- 单次升级: 打开文件 -> fota.init/wait -> 分块写入 -> MD5校验 -> finish
-- 与无UI版步骤5~8完全一致, 仅增加进度上报; 返回 true=成功(内部会重启), false=失败
local function do_upgrade(path)
    local total_size = io.fileSize(path) or 0
    log.info("FOTA_USB_UI", "开始升级", path, "大小", total_size .. "B")

    -- 步骤4: 打开升级包文件
    local fd = io.open(path, "rb")
    if not fd then
        log.error("FOTA_USB_UI", "找不到升级包文件: ", path)
        report_progress(0, total_size, "打开文件失败")
        sys.publish("FOTA_RESULT", false, "打开升级包文件失败:\n" .. path)
        return false
    end

    -- 步骤5: FOTA初始化并等待底层准备就绪
    report_progress(0, total_size, "初始化FOTA...")
    if not fota.init() then
        log.error("FOTA_USB_UI", "FOTA初始化失败")
        fd:close()
        sys.publish("FOTA_RESULT", false, "FOTA初始化失败")
        return false
    end
    while not fota.wait() do
        sys.wait(100)
    end
    log.info("FOTA_USB_UI", "底层准备就绪")

    -- 步骤6: 分块读取U盘文件到zbuff缓冲区, 逐段写入fota分区
    -- 进度按约1%节流上报, 避免每4KB刷一次UI
    local step = (total_size > 200 * READ_BLOCK) and (total_size // 100) or READ_BLOCK
    local last_report = 0
    local buff = zbuff.create(READ_BLOCK)
    local write_total = 0
    local write_done = false

    while true do
        -- fd:fill把文件数据读入zbuff, 不移动zbuff指针, 返回实际读取长度
        local ok, len = fd:fill(buff, 0, READ_BLOCK)
        if not ok or not len or len <= 0 then
            break -- 文件读取结束
        end
        -- 设置zbuff实际数据长度, 供fota.run按此长度写入
        buff:used(len)
        write_total = write_total + len

        local result, isDone, cache = fota.run(buff)
        log.debug("fota.run", result, isDone, cache)
        if not result then
            log.error("FOTA_USB_UI", "fota写入失败", result, isDone, cache)
            break
        end
        if isDone then
            -- 全部数据写入完成(底层已识别到升级包末尾)
            write_done = true
            break
        end

        if write_total - last_report >= step or write_total == total_size then
            last_report = write_total
            report_progress(write_total, total_size, "正在写入升级包 (fota.run)")
        end
    end
    fd:close()
    log.info("FOTA_USB_UI", "升级包读取写入结束, 累计", write_total, "字节")

    -- 步骤7: 处理写入结果
    if not write_done then
        if write_total == 0 then
            log.error("FOTA_USB_UI", "升级包为空或读取失败")
            report_progress(0, total_size, "升级包为空或读取失败")
            sys.publish("FOTA_RESULT", false, "升级包为空或读取失败\n(U盘可能在升级中被拔出)")
        else
            log.error("FOTA_USB_UI", "升级包不完整或写入出错, 升级失败")
            report_progress(write_total, total_size, "写入出错, 升级失败")
            sys.publish("FOTA_RESULT", false, "升级包不完整或写入出错\n请重新选择升级包重试")
        end
        -- fota.finish(false) 结束升级流程, 参数false表示升级流程失败
        fota.finish(false)
        return false
    end

    -- 步骤8: 等待底层MD5校验结束(最多3秒)
    report_progress(total_size, total_size, "等待底层MD5校验...")
    local verified = false
    for i = 1, 30 do
        sys.wait(100)
        local succ, fotaDone = fota.isDone()
        if not succ then
            log.error("FOTA_USB_UI", "校验过程出错")
            break
        end
        if fotaDone then
            verified = true
            break
        end
    end

    if not verified then
        log.error("FOTA_USB_UI", "校验超时或失败, 升级失败")
        sys.publish("FOTA_RESULT", false, "MD5校验超时或失败\n请确认升级包与当前固件版本匹配")
        fota.finish(false)
        return false
    end

    -- 校验通过, 重启后bootloader自动应用fota分区数据完成升级
    log.info("FOTA_USB_UI", "校验通过, 升级成功, 1s后重启")
    sys.publish("FOTA_RESULT", true, "升级包校验通过\n1秒后自动重启应用升级")
    fota.finish(true)
    sys.wait(1000)
    rtos.reboot()
    return true -- 不会执行到这里, 仅为语义完整
end

-- ==================== 主任务 ====================
local function fotaUsbDiskUiTask()
    -- 开机即进入HOST主机模式并常驻(UI版没有"5秒自动触发", USB必须一直可感知U盘插入)
    if not enter_host_mode() then
        sys.publish("FOTA_RESULT", false, "USB切换主机模式失败\n请重启设备重试")
        return
    end

    local first_pass = true -- 首轮: 检查U盘是否已插入(兼容开机前已插好); 之后: 事件等待
    while true do
        -- 步骤A: 检查/等待U盘插入
        if first_pass then
            first_pass = false
            -- 开机首轮: 切HOST后给2秒宽限, U盘开机前已插好的情况枚举事件会在这期间到达
            if not msc_connected then
                sys.waitUntil("USB_MSC_CONNECT", 2000)
            end
        else
            -- 非首轮: 必须等新的插入事件(点✕/挂载失败后U盘可能还插着, 需重新插拔触发)
            sys.waitUntil("USB_MSC_CONNECT")
        end

        if not msc_connected or not usb_app_id then
            -- 检查未插入, 回到上面继续等事件
        elseif not mount_and_report() then
            -- 挂载失败: 弹窗已提示, 等用户拔插U盘后重新触发
            sys.wait(2000)
        else
            -- 步骤B: 用户交互会话(升级失败重试在会话内循环, 不经过步骤A)
            local in_session = true
            while in_session and disk_mounted do
                user_start = false
                user_path = nil
                while not user_start and disk_mounted and not close_req do
                    sys.wait(200)
                end

                if close_req then
                    -- 用户点✕: unmount回待机页(UI已自行切页), 重新插拔U盘才会再次扫描
                    close_req = false
                    pcall(fatfs.unmount, MOUNT_POINT)
                    disk_mounted = false
                    in_session = false
                    log.info("FOTA_USB_UI", "用户关闭选择页, U盘已卸载")
                elseif disk_mounted and user_start then
                    log.info("FOTA_USB_UI", "=== 用户确认升级: ", user_path, " ===")
                    local ok = do_upgrade(user_path)
                    if not ok then
                        -- 失败重试路径: 保持HOST模式, 重新挂载扫描, 用户可直接换包
                        -- 注意: 不能切回DEVICE模式, 否则之后就感知不到U盘了
                        log.info("FOTA_USB_UI", "升级失败, 重新扫描U盘供用户重试")
                        pcall(fatfs.unmount, MOUNT_POINT)
                        disk_mounted = false
                        sys.wait(500)
                        in_session = mount_and_report()
                    end
                    -- 成功路径已在 do_upgrade 内重启, 不会走到这里
                end
                -- U盘被拔出: 回调里已unmount并发UDISK_REMOVED, 会话因disk_mounted=false退出
            end
        end
    end
end

-- ==================== 订阅UI指令 ====================

-- 用户二次确认后触发
sys.subscribe("FOTA_UPGRADE_START", function(path)
    user_path = path
    user_start = true
end)

-- UI点文件夹/[◀返回]: 请求列目录(校验路径必须在U盘挂载点内, 防逃逸)
sys.subscribe("UDISK_LIST_REQ", function(dir)
    if type(dir) ~= "string" or #dir < #MOUNT_POINT or dir:sub(1, #MOUNT_POINT) ~= MOUNT_POINT then
        log.warn("FOTA_USB_UI", "非法目录请求, 忽略", tostring(dir))
        return
    end
    if disk_mounted then
        publish_dir(dir)
    end
end)

-- 用户点✕: 请求关闭选择页(主任务循环里做unmount, 回调上下文不做阻塞操作)
sys.subscribe("UDISK_CLOSE", function()
    close_req = true
end)

-- UI"刷新"按钮: 重新挂载扫描
sys.subscribe("UDISK_RESCAN", function()
    if disk_mounted then
        pcall(fatfs.unmount, MOUNT_POINT)
        disk_mounted = false
        sys.wait(300)
    end
    if msc_connected and usb_app_id then
        mount_and_report()
    end
end)

-- ==================== 模块自启动 ====================
-- 参考fota2 self_server demo的update模块: main.lua只负责require, 本模块被加载即自行启动
-- 顺序即依赖: 上电时序/显示/触摸 -> 建界面 -> 业务核心常驻任务 -> 点亮背光
sys.taskInit(function()
    if not lcd_tp.init() then
        log.error("fota_usb_disk_ui", "显示/触摸初始化失败, demo无法继续")
        return
    end

    ui.build()

    -- 常驻主机模式 + 等U盘 + 等用户确认 + 升级 主循环
    sys.taskInit(fotaUsbDiskUiTask)

    -- 界面首帧已就绪, 最后点亮背光, 避免上电花屏
    lcd_tp.backlight_on()
    log.info("fota_usb_disk_ui", "U盘FOTA升级(有UI版)已就绪, 请插入升级U盘")
end)

return M
