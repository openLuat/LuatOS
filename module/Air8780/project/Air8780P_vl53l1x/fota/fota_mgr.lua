--[[
@module  fota_mgr
@summary libfota2远程升级管理模块，含版本文件管理和首次启动检测
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件为libfota2远程升级的管理模块，核心业务逻辑为：
1、FOTA升级检查与下载
2、版本文件管理（保存/读取）
3、FOTA升级后的首次启动检测

升级流程：
1. 调用 check_and_upgrade() 检查是否有新版本
2. 有新版 → 下载升级包 → 下载成功返回 true → 调用方重启设备
3. 重启后首次运行 → check_first_boot() 检测到版本不一致 → 上报升级结果
4. 上报完成后调用 clear_version_file() 清除标记

本文件的对外接口有4个：
1、fota_mgr.check_first_boot()：检测是否为FOTA升级后的首次启动
2、fota_mgr.check_and_upgrade(max_wait_s)：检查并执行FOTA升级
3、fota_mgr.get_last_result()：获取最后一次FOTA结果
4、fota_mgr.clear_version_file()：清除版本标记文件
]]

-- ==================== 加载扩展库 ====================

-- libfota2: 合宙FOTA升级扩展库
-- 实现HTTP下载升级包的底层逻辑，自动拼接URL和版本号
-- 依赖PRODUCT_KEY在main.lua中定义
local libfota2 = require "libfota2"

-- ==================== 模块表 ====================

-- fota_mgr 为模块对外接口表，所有对外函数注册在此表上
local fota_mgr = {}

-- ==================== 内部状态 ====================

-- g_fota_running: FOTA升级是否正在进行中
-- 用于防止重复调用
local g_fota_running = false

-- g_fota_result: FOTA回调返回码
-- nil=尚未执行，0=成功下载，非0=各种失败原因
-- 用于任务1（PSM+超时管理）判断是否需要等待
local g_fota_result = nil

-- G_FOTA_FILE: 版本标记文件的路径
-- 文件内容格式: "VERSION,PROJECT"
-- 例如: "001.999.000,Air8780P_VL53L1X"
-- 用于检测FOTA升级后的首次启动
local G_FOTA_FILE = "/fota_version.txt"

-- ==================== FOTA回调 ====================

--[[
libfota2升级回调处理函数

当libfota2框架完成升级检查或下载后，自动调用此回调。
回调参数 ret 表示FOTA状态码。

回调完成后发布FOTA_END消息，通知PSM+管理任务：
    1、如果 ret==0（成功下载），任务1看到后会让系统进入重启流程
    2、如果 ret!=0（失败或无升级），任务1在等待超时后进入PSM+

@param number ret FOTA返回码
    0 — 升级包下载成功，需要重启以应用升级
    1 — 连接FOTA服务器失败（网络不通或DNS解析失败）
    2 — 升级包URL错误（PRODUCT_KEY不匹配）
    3 — 与FOTA服务器的连接断开
    4 — 接收报文错误（下载不完整或校验失败），也可能是已是最新版本
    5 — 版本号格式错误（VERSION不符合XXX.YYY.ZZZ格式）
]]
local function fota_callback(ret)
    log.info("fota_mgr", "FOTA回调 ret=", ret)

    -- 清除运行中标志
    g_fota_running = false
    g_fota_result = ret

    -- 根据返回码打印详细日志
    -- 参考libfota2文档中各返回码的含义
    if ret == 0 then
        log.info("fota_mgr", "FOTA升级包下载成功，准备重启")
    elseif ret == 1 then
        log.info("fota_mgr", "FOTA连接失败")
    elseif ret == 2 then
        log.info("fota_mgr", "FOTA URL错误")
    elseif ret == 3 then
        log.info("fota_mgr", "FOTA服务器断开")
    elseif ret == 4 then
        log.info("fota_mgr", "FOTA接收报文错误或已是最新版本")
    elseif ret == 5 then
        log.info("fota_mgr", "FOTA版本号格式错误")
    else
        log.info("fota_mgr", "FOTA未知返回码", ret)
    end

    -- 发布FOTA结束消息，通知PSM+管理任务（任务1）
    -- 任务1等待此消息后检查g_fota_result，决定是否重启或进入PSM+
    sys.publish("FOTA_END")
end

-- ==================== 版本文件管理（内部函数） ====================

--[[
保存当前版本信息到标记文件

文件中保存当前PROJECT和VERSION，格式：VERSION,PROJECT
下次启动时通过read_version读取并比对，判断是否为FOTA后的首次启动

文件路径：/fota_version.txt（存储在文件系统中，重启后保留）
]]
local function save_version()
    local info = VERSION .. "," .. PROJECT
    io.writeFile(G_FOTA_FILE, info)
    log.info("fota_mgr", "保存版本信息到文件:", info)
end

--[[
从标记文件读取版本信息

@return string 文件内容，格式"VERSION,PROJECT"
    例如："001.999.000,Air8780P_VL53L1X"
@return nil 文件不存在或内容为空
    首次运行时文件不存在，属于正常情况
]]
local function read_version()
    local data = io.readFile(G_FOTA_FILE)
    if data and #data > 0 then
        return data
    end
    return nil
end

-- ==================== API：检测FOTA后首次启动 ====================

--[[
检测是否为FOTA升级后的首次启动

fota_mgr.check_first_boot()

本函数通过比对标记文件中的版本号与当前运行版本号来判断：
    1、如果标记文件不存在 → 首次运行，保存版本信息，返回nil
    2、如果版本号一致 → 正常启动，更新标记文件，返回nil
    3、如果版本号不一致 → FOTA升级后首次启动，返回升级对比信息

本函数应在main.lua中require完成后尽早调用，以便在数据上报时包含升级信息。
调用后会自动更新标记文件为当前版本。

@return string
含义：若为FOTA后首次启动，返回包含升级前后版本信息的字符串
示例值：
    "升级前: PROJECT=Air8780P_VL53L1X VERSION=001.999.000 ; 升级后: PROJECT=Air8780P_VL53L1X VERSION=001.999.001"
@return nil
含义：非FOTA首次启动（正常启动或首次运行）

@usage
local fota_info = fota_mgr.check_first_boot()
if fota_info then
    log.info("fota_mgr", "检测到FOTA升级:", fota_info)
    -- 后续数据上报时包含此信息
end
]]
function fota_mgr.check_first_boot()
    -- 读取上次保存的版本信息
    local old_info = read_version()

    -- 文件不存在说明是第一次运行，直接保存当前版本
    if not old_info then
        save_version()
        return nil
    end

    -- 解析文件内容：格式为 "VERSION,PROJECT"
    -- 使用逗号分隔
    local comma_pos = string.find(old_info, ",")
    if not comma_pos then
        -- 文件格式异常，覆盖写入当前版本
        save_version()
        return nil
    end

    -- 提取升级前的版本号和项目名
    local old_version = string.sub(old_info, 1, comma_pos - 1)
    local old_project = string.sub(old_info, comma_pos + 1)

    -- 比对版本号或项目名是否发生变化
    if old_version ~= VERSION or old_project ~= PROJECT then
        -- 版本变化：说明经历了FOTA升级并重启
        local result_str = string.format(
            "升级前: PROJECT=%s VERSION=%s ; 升级后: PROJECT=%s VERSION=%s",
            old_project, old_version, PROJECT, VERSION
        )
        log.info("fota_mgr", "检测到FOTA升级后的首次启动", result_str)
        save_version()
        return result_str
    else
        -- 版本一致：正常启动
        save_version()
        return nil
    end
end

-- ==================== API：获取FOTA结果 ====================

--[[
获取最后一次FOTA回调的结果

fota_mgr.get_last_result()

本函数供PSM+管理任务（任务1）读取FOTA结果。
任务1在收到FOTA_END消息后调用此函数判断是否需要重启：
    0 → FOTA成功，重启设备
    非0 → FOTA失败或无更新，进入PSM+

@return number
含义：FOTA返回码
    nil  — 尚未执行过FOTA检查
    0    — 升级包下载成功
    1    — 连接失败
    2    — URL错误
    3    — 服务器断开
    4    — 接收报文错误或已是最新版本
    5    — 版本号格式错误

@usage
if fota_mgr.get_last_result() == 0 then
    log.info("fota_mgr", "FOTA成功，准备重启")
end
]]
function fota_mgr.get_last_result()
    return g_fota_result
end

-- ==================== API：执行FOTA升级 ====================

--[[
检查并执行FOTA升级

fota_mgr.check_and_upgrade(max_wait_s)

本函数完成以下工作：
1、保存当前版本信息到标记文件
2、发布FOTA_UPGRADING消息通知PSM+任务延长等待
3、调用libfota2.request发起升级检查/下载
4、等待FOTA结果，最长max_wait_s秒
5、返回是否需要重启

注意：
1、libfota2内部会自动检查是否需要升级
2、如果有新版本，libfota2会自动下载
3、下载完成后fota_callback会被调用，ret=0表示下载成功
4、本函数返回true后，调用方需执行rtos.reboot()

@param number max_wait_s
含义：FOTA等待最长时间(秒)
取值范围：正整数
    如果网络状况好，通常10~30秒可完成
    建议设置300~600秒（5~10分钟），为弱网环境留出重试时间
是否必选：必选
建议值：600

@return boolean
含义：true=升级包已下载需要重启，false=无升级或升级失败

@usage
local need_reboot = fota_mgr.check_and_upgrade(600)
if need_reboot then
    rtos.reboot()
end
]]
function fota_mgr.check_and_upgrade(max_wait_s)
    log.info("fota_mgr", "开始检查FOTA升级...")

    -- 第一步：保存当前版本（用于下次启动时比对）
    save_version()
    g_fota_running = true

    -- 第二步：通知PSM+管理任务（任务1）延长等待
    -- 任务1原本在psm_entry_max_s秒后强制进PSM+
    -- 收到FOTA_UPGRADING后会改为等待FOTA_END
    sys.publish("FOTA_UPGRADING")

    -- 第三步：发起FOTA请求
    -- libfota2.request内部流程：
    --   1. 构造URL：HTTP GET iot.openluat.com/api/...
    --   2. 下载升级包（如果有）
    --   3. 下载完成后调用fota_callback
    -- opts可以传自定义参数，此处传空table使用默认配置
    local opts = {}
    libfota2.request(fota_callback, opts)

    -- 第四步：等待FOTA结果，最长max_wait_s秒
    -- 如果超时仍未收到FOTA_END，说明网络不好
    sys.waitUntil("FOTA_END", max_wait_s * 1000)

    -- 第五步：判断结果
    if g_fota_result == 0 then
        log.info("fota_mgr", "FOTA升级包已下载，需要重启模块")
        return true
    end

    log.info("fota_mgr", "FOTA检查完成(无升级或升级失败)")
    return false
end

-- ==================== API：清除版本标记文件 ====================

--[[
清除版本标记文件

fota_mgr.clear_version_file()

在以下场景需要调用：
1、FOTA升级后首次启动，上报完成升级信息后
2、无网络时跳过上报，需要清除文件以免下次启动再次上报
3、版本文件已不再需要时

清除后，下次启动时check_first_boot()会认为是最新版本，不会再返回FOTA信息。

@usage
fota_mgr.clear_version_file()
]]
function fota_mgr.clear_version_file()
    os.remove(G_FOTA_FILE)
    log.info("fota_mgr", "已删除版本标记文件")
end

return fota_mgr
