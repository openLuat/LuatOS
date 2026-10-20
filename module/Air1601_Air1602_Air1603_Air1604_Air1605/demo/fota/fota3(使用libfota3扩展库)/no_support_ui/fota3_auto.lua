--[[
@module  fota3_auto
@summary libfota3 无UI自动升级功能模块
@version 1.0
@date    2026.08.24
@author  马梦阳

@注意     仅合宙内部使用

@usage
使用libfota3扩展库实现无UI设备的自动FOTA升级功能。

特点：
1、不使用 on_confirm 回调，检测到新版本自动下载并重启；
2、使用 on_status 回调记录升级状态日志；
3、支持自动定时检测，默认24小时检测一次；

适用场景：
    - DTU、传感器、网关等无屏幕设备
    - 无人值守场景
]]


-- 项目密钥：在 iot.openluat.com 平台主页面上方导航栏 Turnkey 页面中获取，仅支持合宙内部使用
local PRODUCT_KEY = "your_project_key_here"


-- 加载libfota3扩展库
local libfota3 = require "libfota3"


-- 循环打印版本号, 方便看版本号变化, 非必须
local function print_version()
    log.info("fota3", "脚本版本号", VERSION, "core版本号", rtos.version())
end
sys.timerLoopStart(print_version, 3000)


-- 启动FOTA自动升级任务
local function fota3_auto_task()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("fota3_auto", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    -- 检测到了IP_READY消息
    log.info("fota3_auto", "recv IP_READY", socket.dft())

    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    if "your_project_key_here" == _G.PRODUCT_KEY then
        while true do
            sys.wait(1000)
            log.info("fota3", "请修改正确的PRODUCT_KEY")
        end
    end

    -- 启动 FOTA 自动升级
    libfota3.request({
        -- 项目密钥：在 iot.openluat.com 平台主页面上方导航栏 Turnkey 页面中获取，仅支持合宙内部使用
        project_key = PRODUCT_KEY,

        -- 脚本名称：与项目名保持一致即可
        script_name = PROJECT,

        -- 脚本版本：与 VERSION 保持一致
        script_version = VERSION,

        -- 启用自动定时检测
        auto = true,

        -- 自动检测间隔：24小时（86400秒）
        -- 可根据需求调整，建议不要太频繁
        interval = 86400,

        -- 状态回调：记录升级状态日志
        on_status = function(status, msg, percent)
            if status == "downloading" then
                -- 下载进度：percent 为 0-100
                log.info("fota3", string.format("[%s] %s %d%%", status, msg, percent or 0))
            else
                -- 其他状态
                log.info("fota3", string.format("[%s] %s", status, msg))
            end
        end,

        -- 注意：无UI设备不需要 on_confirm 回调
        -- libfota3 检测到新版本后会自动下载并重启
    })
end

-- 初始化FOTA任务
sys.taskInit(fota3_auto_task)


-- 演示手动触发升级检测，可以根据需求打开
-- sys.timerLoopStart(function()
--     libfota3.check_update()
-- end, 4 * 3600000) -- 每4小时手动检测一次
