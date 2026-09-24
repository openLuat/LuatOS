--[[
@module  config
@summary 系统配置模块
@version 1.0
@date    2026.10.16
@author  王城钧
@usage
本模块提供系统配置参数，包括服务器地址、端口、超时时间等。
]]

local config = {}

-- 服务器配置
config.server = {
    host = "api.luatos.com",
    port = 443,
    api_path = "/iot/smart_locker",
    timeout = 5000, -- 服务器请求超时时间(ms)
    retry_count = 3, -- 服务器请求重试次数
    retry_interval = 2000 -- 服务器请求重试间隔(ms)
}

-- 设备标识配置
config.device = {
    -- 设备唯一标识（所有接口的 deviceid 参数）
    -- 默认留空：自动使用模组 STA MAC 地址（如 "C8C2C6906511"，Air1601 WiFi 模组）
    -- 仅当服务器要求特定格式设备号时才填，如 "AB123456789"；
    -- 留空 "" 时按 MAC 地址(优先) → IMEI → MCU唯一ID 顺序自动生成
    device_id = ""
}

-- 柜子配置
config.locker = {
    total_boxes = 7, -- 总箱子数量（7路控制板）
    available_boxes = 7, -- 可用箱子数量
    used_boxes = 0, -- 已使用箱子数量
    -- 柜子分配策略（刷脸存件/普通存件共用）
    allocation = {
        strategy = "round_robin", -- 分配策略：round_robin=轮询均衡 / first_available=顺序取最小
        round_robin_start = 1, -- 轮询起始柜号（含）
        round_robin_end = 5, -- 轮询结束柜号（含）：先在 1-5 之间轮询均衡
        fallback_outside = true -- 轮询范围(1-5)全部占用时，是否回退到范围外柜子(6-7)
    },
    box_types = {"小", "中", "大"}, -- 箱子类型
    box_sizes = {
        small = {width = 30, height = 40, depth = 40},
        medium = {width = 40, height = 50, depth = 50},
        large = {width = 50, height = 60, depth = 60}
    }
}

-- 串口配置
config.serial = {
    uartid = 1, -- 串口号（485 串口用 uart1，uart3 留给 airlink 4G）
    baudrate = 9600, -- 波特率
    data_bits = 8, -- 数据位
    stop_bits = 1, -- 停止位
    parity = 0, -- 校验位 0:无校验, 1:奇校验, 2:偶校验
    flow_control = 0, -- 流控 0:无流控
    timeout = 2000 -- 超时时间(ms)
}

-- 485总线配置
config.rs485 = {
    pin = 8, -- 485使能引脚
    active_high = true -- 高电平有效
}

-- 网络配置
config.network = {
    connect_timeout = 10000, -- 网络连接超时(ms)
    reconnect_interval = 5000, -- 重连间隔(ms)
    max_reconnects = 10 -- 最大重连次数
}

-- 系统配置
config.system = {
    log_level = 2, -- 日志级别 0:debug, 1:info, 2:warn, 3:error
    time_zone = 8, -- 时区 +8:00
    heartbeat_interval = 30000, -- 心跳间隔(ms)
    status_check_interval = 60000 -- 状态检查间隔(ms)
}

-- 存取件配置
config.business = {
    deposit_timeout = 60000, -- 存件超时时间(ms)
    pickup_timeout = 60000, -- 取件超时时间(ms)
    verify_timeout = 30000, -- 验证超时时间(ms)
    max_boxes_per_user = 1, -- 每个用户最多使用箱子数量
    storage_time_limit = 86400, -- 最大存储时间(s) - 24小时
    warning_time = 3600, -- 超时警告时间(s) - 1小时
    overtime_fee = 0.5 -- 超时费用(元/小时)
}

-- AirCloud配置
config.aircloud = {
    enabled = true, -- 是否启用AirCloud功能
    auto_reconnect = true, -- 自动重连
    reconnect_interval = 10, -- 重连间隔(秒)
    max_reconnects = 5 -- 最大重连次数
}

-- FOTA 升级配置（libfota3 合宙整机成品FOTA）
config.fota = {
    enabled = true,       -- 是否启用FOTA
    project_key = "6Olgc34lgwPUOzTAXWqGbMLS1DMUPMok",     -- FOTA项目密钥（必填，否则无法检测）
    script_name = _G.PROJECT, -- 脚本名称，默认取 _G.PROJECT
    script_version = _G.VERSION, -- 脚本版本，默认取 _G.VERSION
    auto = true,          -- 是否自动定时检测
    interval = 60,      -- 自动检测间隔（秒），默认1小时
}

-- 人脸识别配置（AirCAMERA_1034）
config.face = {
    uartid = 2,              -- 人脸模块串口（uart2，115200 8N1）
    baudrate = 115200,       -- 波特率
    power_pin = 73,          -- UVC 摄像头使能引脚
    sensor_width = 960,      -- UVC 摄像头采集宽度（AirCAMERA_1034 最高支持 960×480@15fps，勿用 1280×720）
    sensor_height = 480,     -- UVC 摄像头采集高度
    usb_port = 1,            -- USB 端口号
    register_timeout = 15,   -- 人脸注册超时(秒)
    verify_timeout = 15,     -- 人脸验证超时(秒)
    bind_prefix = "face_bind_", -- 人脸↔柜号绑定 fskv 键前缀
    -- 刷脸界面摄像头预览（airui.camera 组件）
    preview = {
        enabled = true,      -- 是否开启预览
        --    CPU 被占满导致红外人脸识别(UART2)处理不过来 → 录入失败
        width = 320,         -- 预览目标分辨率宽（模块支持：960×480/864×480/800×480/480×320/320×240）
        height = 240,
        fps = 10,
        fit = "cover",       -- 画面适配：center/contain/cover/stretch
        rotation = 90,       -- 摄像头画面旋转（若固件支持）
        -- ===== 人脸识别与预览并行（参考版 8601寄存柜_zuizhong 方案）=====
        --   serial       ：原逻辑（停流 → 复位模组 → 识别），画面在识别期间不刷新，出问题可回退
        --   auto         ：预览不停流直接识别；识别失败自动降级为 serial 重试一次（推荐）
        --   concurrent   ：一律并行，失败不降级
        mode = "auto",
        busy_fps = 3,        -- 并行模式下的预览帧率：压低帧率把 CPU 让给 UART2 人脸数据，避免识别超时
        ready_extra_wait = 500, -- 预览画面就绪后额外等待(ms)，确保 UART2 人脸模组稳定后再通知业务层
        -- 进窗后等待摄像头连接的超时(ms)：模组已上电且枚举过时，preview 注册回调后不会再有
        --   EV_CONNECT → 只能靠 GPIO73 断电重枚举触发，故这里要短（实测 2500ms 会让每次开窗
        --   白黑 2.5s）；400ms 内没连上就立刻断电重试，约 1.5~2s 出画面。
        connect_wait = 400,
        retry_wait = 3000,   -- 断电重试后再次等待连接的超时(ms)：仍未连接才判定预览不可用
        reconnect_wait = 2500, -- 断开后等待自动重连的宽限期(ms)：超时仍未连上才判定预览不可用
        close_grace = 400,   -- 停流前宽限(ms)：excamera.close() 内部会 free 双缓冲，等一帧时间让
                             --   在途帧回调跑完再停流，降低“释放缓冲 vs 帧回调”竞争（死机）
                             -- 注：组件销毁时机在 face_preview 内已固定为“停流之后”，不要再改回去
        start_delay = 1500,  -- 画面就绪后等待多久发起识别(ms)，留给用户对准摄像头的时间
        ready_timeout = 6000, -- 等待预览就绪的超时兜底(ms)：超时退回串行识别，避免界面卡死
        retry_serial = true, -- 并行识别失败时是否自动降级为串行（停流+复位）重试一次
    },
    -- 刷脸拍照留底（存件/取件发起识别前，抓取一帧预览画面保存到SD卡）
    photo = {
        enabled = true,          -- 是否开启拍照留底
        sd_path = "/sd/photo",   -- 照片保存目录（SD卡；未挂载时自动回退 /ram/photo）
        timeout = 2000,          -- 等待摄像头画面超时(ms)
    }
}

-- 主配置（main.lua 行为开关）
config.main = {
    -- 开机预下载小程序码：默认关闭！
    -- QR 图片为 HTTPS 大帧连续下载，会打爆 UART3(airlink→6205) RX FIFO（uart3 err 连发、帧错位），
    -- 导致 airlink 链路损坏、DNS/HTTP 全部失败，只能重启恢复（固件层溢出，脚本无法根治）。
    -- 副本一直没出问题正是因为它开机不下载 QR。QR 已在 flash 时可安全开启（会直接跳过）。
    qr_predownload = false,
}

-- 函数：获取配置值
function config.get(key, default)
    local value = config
    for k in string.gmatch(key, "[^%.]+") do
        if type(value) == "table" then
            value = value[k]
        else
            value = nil
            break
        end
    end
    return value or default
end

-- 函数：设置配置值
function config.set(key, value)
    local tbl = config
    local keys = {}
    for k in string.gmatch(key, "[^%.]+") do
        table.insert(keys, k)
    end
    
    for i = 1, #keys - 1 do
        local k = keys[i]
        if not tbl[k] or type(tbl[k]) ~= "table" then
            tbl[k] = {}
        end
        tbl = tbl[k]
    end
    
    tbl[keys[#keys]] = value
end

-- 初始化配置
function config.init()
    log.info("config", "配置模块初始化")
    
    -- 如果没有配置文件，使用默认值
    -- 可以添加读取配置文件的逻辑
end

-- 导出配置模块
return config
