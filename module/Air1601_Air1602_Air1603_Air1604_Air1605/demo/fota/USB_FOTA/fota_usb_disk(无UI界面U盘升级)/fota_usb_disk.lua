--[[
@module  fota_usb_disk
@summary U盘FOTA升级功能模块（无UI界面版本）
@version 1.0
@date    2026.11.10
@author  谌程
@usage
-- U盘FOTA升级功能（无UI界面通用版）
-- 适用模块：Air8607w、Air8603系列、Air8605系列（同为Air1603平台家族，Lua API一致）
-- 注意：Air8603/Air8605开发板上USB座的+5.5V由JW5357升压产生，EN脚接UVC_EN(GPIO58)，
--       必须拉高GPIO58才有供电，否则U盘枚举不到（两块板原理图均已证实），见USB_PWR_PIN配置
-- 数据来源为U盘上的升级包文件，整体架构仿照 fota_uart.lua：
--   开机5秒后自动进入升级模式 -> USB切换为主机模式 -> 等待U盘插入并枚举 ->
--   fatfs挂载U盘 -> 分块读取升级包文件到zbuff缓冲区 -> fota.run分段写入fota分区 ->
--   fota.isDone等待底层MD5校验 -> fota.finish -> 自动重启完成升级

升级包固定文件名说明（仿照fota_file.lua固定路径的用法）:
1. 升级包文件名固定为 update.bin，放在U盘根目录下；
2. U盘需要格式化为FAT32格式；
3. 升级包用Luatools制作：先把新旧版本分别生成量产文件，再通过
   工具上栏 luatOS->固件工具->差分包/整包升级包制作 生成升级包；

操作步骤:
1. 先把脚本和固件烧录到模块里，并确认开机；
2. 开机5秒后设备自动进入U盘升级模式（USB会切换为HOST主机模式）；
3. 插入带有update.bin的U盘，设备自动挂载并开始升级；
4. 升级包校验通过后，设备提示1秒后重启，重启后自动应用升级；
5. 升级结果通过日志中的版本号变化来确认；

注意事项:
- USB切换为HOST主机模式后，USB虚拟串口（CDC）功能不可用，luatools需要通过
  UART0物理串口（日志串口）查看日志；
- 本功能依赖固件的usb库（主机模式）和fatfs库（USB挂载），请确认固件版本支持；
- 升级过程中如果发生错误，会自动恢复USB为从机模式，重新上电可再次升级；
- 升级成功设备会自动重启；

本文件没有对外接口，直接在main.lua中require "fota_usb_disk"就可以加载运行；
]]

-- U盘挂载点
local MOUNT_POINT = "/udisk"

-- 固定的升级包文件路径, U盘根目录下必须有此文件名的升级包
local filePath = "/udisk/update.bin"

-- USB总线id, 如果芯片只有1条USB线, 填0
local USB_ID = 0

-- U盘供电使能脚(UVC_EN):
-- Air8603开发板(J14 USB-A母座)和Air8605开发板(人脸识别USB Type-A母座)均为GPIO58
-- 其他模块/自研板按各自原理图的USB供电使能脚修改; 无需软件控制供电的传nil即可跳过
local USB_PWR_PIN = 58

-- 每次从U盘读取并写入fota分区的大小, 最大不应超过4K
local READ_BLOCK = 4096

-- 等待U盘插入的超时时间, 单位ms
local USB_WAIT_TIMEOUT = 30000

-- 全局状态变量
local upgrade_active = false   -- 升级流程是否已激活
local msc_connected = false    -- U盘(MSC类设备)是否已枚举连接
local disk_mounted = false     -- U盘是否已挂载
local usb_app_id = nil         -- U盘枚举成功后底层分配的app_id, 挂载时必须使用

-- USB事件回调: 感知U盘插入和拔出
local function usb_event_cb(id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT and class == usb.MSC then
        log.info("FOTA_USB_DISK", "检测到U盘插入", "app_id", app_id)
        usb_app_id = app_id
        msc_connected = true
        sys.publish("USB_MSC_CONNECT")
    elseif event == usb.EV_DISCONNECT and class == usb.MSC then
        log.warn("FOTA_USB_DISK", "U盘已拔出")
        msc_connected = false
        usb_app_id = nil
    end
end

-- 注册USB事件回调, 文件加载时注册一次即可
usb.on(USB_ID, usb_event_cb)

-- 清理资源的函数: 取消挂载并恢复USB为从机模式(虚拟串口), 方便下次升级和luatools查看日志
local function cleanup_resources()
    if disk_mounted then
        fatfs.unmount(MOUNT_POINT)
        disk_mounted = false
    end
    -- 切换USB模式必须在USB外设掉电状态下进行
    pm.power(pm.USB, false)
    usb.mode(USB_ID, usb.DEVICE)
    pm.power(pm.USB, true)
    msc_connected = false
    usb_app_id = nil
    upgrade_active = false
    log.info("FOTA_USB_DISK", "资源已清理, USB已恢复从机模式")
end

-- 触发方式: 开机5秒后自动进入U盘升级模式
sys.taskInit(function()
    sys.wait(5000)
    if not upgrade_active then
        log.info("FOTA_USB_DISK", "开机5秒, 自动进入U盘升级模式")
        upgrade_active = true
        sys.publish("USB_UPGRADE_START")
    end
end)

-- U盘升级任务
local function usbDiskUpgradeTask()
    while true do
        -- 等待升级启动信号
        sys.waitUntil("USB_UPGRADE_START")
        log.info("FOTA_USB_DISK", "=== 进入U盘升级模式 ===")

        -- 步骤0: 给U盘座供电(Air8603/Air8605开发板必须, EN接GPIO58; 配置为nil则跳过)
        if USB_PWR_PIN then
            pcall(gpio.setup, USB_PWR_PIN, 0)
            pcall(gpio.set, USB_PWR_PIN, 1)
            sys.wait(100)
            log.info("FOTA_USB_DISK", "U盘供电脚GPIO", USB_PWR_PIN, "已拉高")
        end

        -- 步骤1: 切换USB为主机模式(必须在USB外设掉电状态下设置)
        pm.power(pm.USB, false)
        local mode_ok = usb.mode(USB_ID, usb.HOST)
        pm.power(pm.USB, true)
        if not mode_ok then
            log.error("FOTA_USB_DISK", "USB切换主机模式失败")
            cleanup_resources()
        else
            -- 步骤2: 等待U盘插入并枚举成功
            log.info("FOTA_USB_DISK", "请插入带有升级包的U盘, 升级包路径应为: ", filePath)
            local wait_time = 0
            while not msc_connected and wait_time < USB_WAIT_TIMEOUT do
                sys.waitUntil("USB_MSC_CONNECT", 1000)
                wait_time = wait_time + 1000
            end
            if not msc_connected then
                log.error("FOTA_USB_DISK", "等待U盘插入超时", USB_WAIT_TIMEOUT, "ms")
                cleanup_resources()
            else
                -- 步骤3: 挂载U盘为文件系统(使用回调返回的app_id, 带重试: 个别U盘枚举完成后需等待才可读)
                sys.wait(500) -- 枚举完成后稍作等待, 让底层稳定
                local mounted = false
                for i = 1, 3 do
                    mounted = fatfs.mount(fatfs.USB, MOUNT_POINT, usb_app_id)
                    if mounted then break end
                    log.warn("FOTA_USB_DISK", "U盘挂载第", i, "/3次失败, 300ms后重试")
                    sys.wait(300)
                end
                if not mounted then
                    log.error("FOTA_USB_DISK", "U盘挂载失败, 请确认U盘为FAT32格式")
                    cleanup_resources()
                else
                    disk_mounted = true
                    log.info("FOTA_USB_DISK", "U盘挂载成功: ", MOUNT_POINT)

                    -- 步骤4: 打开升级包文件
                    local fd = io.open(filePath, "rb")
                    if not fd then
                        log.error("FOTA_USB_DISK", "找不到升级包文件: ", filePath)
                        cleanup_resources()
                    else
                        -- 步骤5: FOTA初始化并等待底层准备就绪
                        log.info("FOTA_USB_DISK", "初始化FOTA...")
                        if not fota.init() then
                            log.error("FOTA_USB_DISK", "FOTA初始化失败")
                            fd:close()
                            cleanup_resources()
                        else
                            log.info("FOTA_USB_DISK", "等待底层准备...")
                            while not fota.wait() do
                                sys.wait(100)
                            end
                            log.info("FOTA_USB_DISK", "底层准备就绪")

                            -- 步骤6: 分块读取U盘文件到zbuff缓冲区, 逐段写入fota分区
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
                                log.info("FOTA_USB_DISK", "准备写入fota包", len, "累计读取", write_total)

                                local result, isDone, cache = fota.run(buff)
                                log.debug("fota.run", result, isDone, cache)
                                if not result then
                                    log.error("FOTA_USB_DISK", "fota写入失败", result, isDone, cache)
                                    break
                                end
                                if isDone then
                                    -- 全部数据写入完成(底层已识别到升级包末尾)
                                    write_done = true
                                    break
                                end
                            end
                            fd:close()
                            log.info("FOTA_USB_DISK", "升级包读取写入结束, 累计", write_total, "字节")

                            -- 步骤7: 处理写入结果
                            if not write_done then
                                if write_total == 0 then
                                    log.error("FOTA_USB_DISK", "升级包为空或读取失败, 请检查U盘中的update.bin")
                                else
                                    log.error("FOTA_USB_DISK", "升级包不完整或写入出错, 升级失败")
                                end
                                -- 调用fota.finish(false)结束升级流程，参数false表示升级流程失败。
                                fota.finish(false)
                                cleanup_resources()
                            else
                                -- 等待底层MD5校验结束
                                local verified = false
                                for i = 1, 30 do  -- 最多等待3秒
                                    sys.wait(100)
                                    local succ, fotaDone = fota.isDone()
                                    if not succ then
                                        log.error("FOTA_USB_DISK", "校验过程出错")
                                        break
                                    end
                                    if fotaDone then
                                        verified = true
                                        break
                                    end
                                end
                                if verified then
                                    -- 升级文件成功写入flash中的fota分区，准备重启设备；
                                    -- 设备重启后，在初始化阶段的运行过程中会自动应用fota分区中的数据完成升级，
                                    -- 最终升级结果可以通过观察日志中的版本号来区分。
                                    log.info("FOTA_USB_DISK", "校验通过, 升级成功, 1s后重启")
                                    -- 调用fota.finish(true)结束升级流程，参数true表示正确走完流程。
                                    fota.finish(true)
                                    cleanup_resources()
                                    sys.wait(1000)
                                    rtos.reboot()
                                else
                                    log.error("FOTA_USB_DISK", "校验超时或失败, 升级失败")
                                    fota.finish(false)
                                    cleanup_resources()
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 本轮升级结束, 等待下一次触发
        log.info("FOTA_USB_DISK", "=== 本轮U盘升级流程结束, 重新上电可再次升级 ===")
    end
end

-- 启动U盘升级任务
sys.taskInit(usbDiskUpgradeTask)
