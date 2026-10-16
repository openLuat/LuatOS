--[[
@module  fota3_ui
@summary libfota3 有UI确认升级功能模块
@version 1.0
@date    2026.08.24
@author  马梦阳

@注意     仅合宙内部使用

@usage
使用libfota3扩展库实现有UI设备的FOTA升级功能。

特点：
1、使用 on_confirm 回调实现用户确认交互；
2、检测到新版本后弹窗让用户确认是否下载；
3、下载完成后弹窗让用户确认是否重启；
4、支持显示下载进度；

适用场景：
    - 手持终端、智能家居面板等有屏幕设备
    - 需要用户确认的升级场景
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


-- ============================================================
-- UI 相关函数（需要根据实际硬件平台实现）
-- ============================================================

-- 存储用户确认结果
local user_confirm_result = nil

--[[
@function show_confirm_dialog
@summary 显示确认对话框（需要根据实际UI框架实现）
@param title string 对话框标题
@param message string 提示信息
@param on_confirm function 确认回调，传入 true/false
@return 无
@description
    此函数需要根据实际硬件平台的UI框架实现。
    示例中使用日志模拟，实际项目中应调用：
    - AirUI 的弹窗组件
    - 或其他GUI框架的对话框API
    
    实现要点：
    1. 显示对话框，包含"确认"和"取消"按钮
    2. 用户点击按钮后调用 on_confirm(true) 或 on_confirm(false)
]]
local function show_confirm_dialog(title, message, on_confirm)
    -- ========================================
    -- 以下是模拟实现，实际项目请替换为真实UI代码
    -- ========================================
    log.info("ui", "========================================")
    log.info("ui", title)
    log.info("ui", message)
    log.info("ui", "========================================")
    
    -- 模拟用户确认（3秒后自动确认）
    -- 实际项目中应等待用户点击按钮
    sys.taskInit(function()
        log.info("ui", "模拟用户确认：3秒后自动确认...")
        sys.wait(3000)
        -- 模拟用户点击"确认"按钮
        on_confirm(true)
    end)
end

--[[
@function show_progress
@summary 显示下载进度（需要根据实际UI框架实现）
@param percent number 进度百分比 0-100
@param message string 进度信息
@return 无
@description
    此函数需要根据实际硬件平台的UI框架实现。
    示例中使用日志打印，实际项目中应更新进度条UI
]]
local function show_progress(percent, message)
    -- ========================================
    -- 以下是模拟实现，实际项目请替换为真实UI代码
    -- ========================================
    log.info("ui", string.format("进度: %d%% - %s", percent, message))
end


-- 启动FOTA带UI确认升级任务
local function fota3_ui_task()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("fota3_ui", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    -- 检测到了IP_READY消息
    log.info("fota3_ui", "recv IP_READY", socket.dft())

    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    if "your_project_key_here" == _G.PRODUCT_KEY then
        while true do
            sys.wait(1000)
            log.info("fota3", "请修改正确的PRODUCT_KEY")
        end
    end

    -- 启动 FOTA 升级（带UI确认）
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
        interval = 86400,

        -- 状态回调：更新UI显示
        on_status = function(status, msg, percent)
            if status == "checking" then
                -- 正在检测更新
                show_progress(0, "正在检测更新...")
                
            elseif status == "new_version" then
                -- 发现新版本：msg 包含版本信息
                log.info("fota3", "发现新版本:", msg)
                
            elseif status == "downloading" then
                -- 下载进度：percent 为 0-100
                show_progress(percent or 0, msg)
                
            elseif status == "download_done" then
                -- 下载完成
                show_progress(100, "下载完成")
                
            elseif status == "download_fail" then
                -- 下载失败
                log.error("fota3", "下载失败:", msg)
                
            elseif status == "rebooting" then
                -- 正在重启
                show_progress(100, "正在重启升级...")
                
            else
                -- 其他状态
                log.info("fota3", string.format("[%s] %s", status, msg))
            end
        end,

        -- 确认回调：显示UI让用户确认
        on_confirm = function(action, info, callback)
            if action == "download" then
                -- 确认下载：info 包含 version, size, fota_sn
                local version = info and info.version or "未知"
                local size = info and info.size or 0
                local size_kb = math.floor(size / 1024)
                
                local message = string.format(
                    "发现新版本: %s\n大小: %d KB\n\n是否下载？",
                    version, size_kb
                )
                
                -- 显示确认对话框
                show_confirm_dialog("固件更新", message, function(ok)
                    log.info("fota3", "用户" .. (ok and "确认" or "取消") .. "下载")
                    callback(ok)
                end)
                
            elseif action == "reboot" then
                -- 确认重启
                show_confirm_dialog("升级确认", "下载完成，是否立即重启升级？", function(ok)
                    log.info("fota3", "用户" .. (ok and "确认" or "取消") .. "重启")
                    callback(ok)
                end)
            end
        end,
    })
end

-- 初始化FOTA任务
sys.taskInit(fota3_ui_task)


-- 演示手动触发升级检测，可以根据需求打开
-- sys.timerLoopStart(function()
--     libfota3.check_update()
-- end, 4 * 3600000) -- 每4小时手动检测一次
