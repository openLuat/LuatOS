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
    -- 留空 "" 时自动生成：MAC 地址(优先，如 "C8C2C6906511"，Air1601 WiFi 模组) → IMEI → MCU唯一ID
    -- 需要指定格式的设备号时可直接填，如 "AB123456789"
    device_id = ""
}

-- 柜子配置
config.locker = {
    total_boxes = 7, -- 总箱子数量（7路控制板）
    available_boxes = 7, -- 可用箱子数量
    used_boxes = 0, -- 已使用箱子数量
    -- ===== 测试开关（生产环境三项都必须为 false）=====
    -- ignore_server_status：true=忽略服务器返回的柜位占用状态，全部柜子按空闲处理；
    --   生产必须 false，否则会把服务器记录为占用的柜子重复分配出去。
    ignore_server_status = true,
    -- ignore_local_occupied：true=忽略本地占用记录（pickup_code_* / face_bind_*）；
    --   与 ignore_server_status 一起打开 = 所有柜子都当空闲，测试时一定选得到柜子；
    --   生产必须 false，否则取件码/人脸绑定占着的柜子会被重复分配给别人。
    ignore_local_occupied = true,
    -- ignore_server_reject：true=服务器拒绝存件（如 code 55 该柜子已占用）也继续开柜，改用本地取件码；
    --   生产必须 false（该笔在服务器无记录，只有本机能取件）。
    ignore_server_reject = true,
    -- 柜子分配策略（刷脸存件/普通存件共用）
    allocation = {
        strategy = "round_robin", -- 分配策略：round_robin=轮询均衡 / first_available=顺序取最小
        round_robin_start = 1, -- 轮询起始柜号（含）
        round_robin_end = 5, -- 轮询结束柜号（含）
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
    uartid = 1, -- 串口号（485 锁控用 uart1）
    baudrate = 9600, -- 波特率
    data_bits = 8, -- 数据位
    stop_bits = 1, -- 停止位
    parity = 0, -- 校验位 0:无校验, 1:奇校验, 2:偶校验
    flow_control = 0, -- 流控 0:无流控
    timeout = 2000 -- 超时时间(ms)
}

-- 485总线配置
config.rs485 = {
    -- 485 收发方向脚 RE/DE（Air8601：GPIO72）
    -- 该脚由 uart.setup 的第 8 个参数自动切换（uart_controller.lua 的 init_uart），
    --   无需在别处 gpio.setup；极性由 uart.setup 第 9 个参数决定（当前 0=接收低电平、发送高电平）
    pin = 72,
}

-- 网络配置
config.network = {
    connect_timeout = 10000, -- 网络连接超时(ms)
    reconnect_interval = 5000, -- 重连间隔(ms)
    max_reconnects = 10 -- 最大重连次数
}

-- 系统配置
config.system = {
    log_level = 2, -- 日志级别 0:debug, 1:info, 2:warn, 3:error（预留项：脚本未调用 log.setLevel，如需按级别过滤日志，请在 main.lua 中启用）
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
    auto = false,         -- 是否自动定时检测（false=按需，只在手动触发时检测）
    -- interval 仅在 auto=true 时生效；按需升级入口：fota_manager.check_update()
    interval = 86400,     -- 自动检测间隔（秒）
}

-- 人脸识别配置（AirCAMERA_1034）
config.face = {
    uartid = 2,              -- 人脸模块串口（uart2，115200 8N1）
    baudrate = 115200,       -- 波特率
    power_pin = 73,          -- UVC 摄像头使能引脚
    -- 人脸状态回传开关（"请正对摄像头/请抬头"等界面引导，界面订阅 FACE_STATE_UPDATE）
    -- 注册/验证时把状态回调透传给模组；如现场出现负载异常可置 false 关闭
    state_callback = true,
    -- ⚠️ 下面 sensor_width/height 本工程的【刷脸预览不读它】：
    --    face_preview 实际用的是 face.preview.width/height（当前 960×480）；
    --    这两项只有 face_demo.lua 等独立测试脚本会用到。调预览分辨率请改 preview 段。
    sensor_width = 960,      -- UVC 采集宽度（AirCAMERA_1034 最高支持 960×480@15fps）
    sensor_height = 480,     -- UVC 采集高度
    usb_port = 1,            -- USB 端口号
    register_timeout = 15,   -- 人脸注册超时(秒)
    verify_timeout = 15,     -- 人脸验证超时(秒)
    bind_prefix = "face_bind_", -- 人脸↔柜号绑定 fskv 键前缀
    -- 刷脸界面摄像头预览（airui.camera 组件）
    preview = {
        enabled = true,      -- 是否开启预览
        -- 预览/抓帧分辨率：UVC 按此分辨率出流，预览画面与拍照留底都用这个尺寸
        --   模块支持：960×480/864×480/800×480/480×320/320×240
        -- 改分辨率时须把 ecface 的 preview_w/preview_h 同步改掉（当前 260×520，1:2）
        --   与参考工程 face_camera_test 取同款：960×480 采集，旋转 90° 后画面为 480×960（1:2）
        width = 960,
        height = 480,
        fps = 10,            -- 预览帧率
        fit = "contain",     -- 画面适配：center/contain/cover/stretch（旋转后与预览框 1:2 同比）
        rotation = 90,       -- 摄像头画面旋转（0/90/180/270，顺时针）；预览与抓帧共用该角度
        -- ===== 人脸识别与预览的并行策略 =====
        --   serial       ：停流 → 复位模组 → 识别，识别期间画面不刷新（最保守）
        --   auto         ：预览不停流直接识别；识别失败自动降级为 serial 重试一次（推荐）
        --   concurrent   ：一律并行，失败不降级
        mode = "auto",
        busy_fps = 3,        -- 并行模式下的预览帧率
        ready_extra_wait = 500, -- 预览画面就绪后额外等待(ms)，之后才通知业务层
        -- 进窗后等待摄像头连接的超时(ms)：模组已上电且枚举过时，preview 注册回调后不会再有
        --   EV_CONNECT → 只能靠 GPIO73 断电重枚举触发，故这里要短（实测 2500ms 会让每次开窗
        --   白黑 2.5s）；400ms 内没连上就立刻断电重试，约 1.5~2s 出画面。
        connect_wait = 400,
        retry_wait = 3000,   -- 断电重试后再次等待连接的超时(ms)：仍未连接才判定预览不可用
        reconnect_wait = 2500, -- 断开后等待自动重连的宽限期(ms)：超时仍未连上才判定预览不可用
        close_grace = 400,   -- 停流前宽限(ms)：等一帧时间让在途帧回调跑完再停流
                             -- 注：停流后组件默认保留（继续显示最后一帧），关窗才销毁；销毁必须晚于停流，保持一致
        start_delay = 1500,  -- 画面就绪后等待多久发起识别(ms)
        ready_timeout = 6000, -- 等待预览就绪的超时兜底(ms)：超时退回串行识别
        retry_serial = true, -- 并行识别失败时是否自动降级为串行（停流+复位）重试一次
    },
    -- 刷脸拍照留底（存件/取件发起识别前，抓取一帧预览画面保存到SD卡）
    photo = {
        enabled = true,          -- 是否开启拍照留底
        sd_path = "/sd/photo",   -- 照片保存目录（SD卡；未挂载时自动回退 /ram/photo）
        timeout = 2000,          -- 等待摄像头画面超时(ms)
        -- 本地照片保留策略（开机后自动清理一次）
        keep_days = 30,          -- 按时间保留（天，0=不按时间清理）
        max_count = 0,           -- 按张数保留最新 N 张（0=不限）
    }
}

-- 事件上报与本地流水
-- 当前策略：开箱 / 关箱 / 存件 / 取件等【事件】云端 + 本地同时落：
--   · 云端：aircloud.report_event() → excloud.send(TLV)，事件内容打包进 BUSINESS_SN(1282) 一条串：
--           格式  事件|box=柜号|ts=时间戳|id=事件唯一ID|ident=业务标识|extra=附加信息
--           示例  OPEN|box=7|ts=1790446739|id=C8C2C693F498-31|ident=|extra=scene=face_store,...
--           另有两条标准字段：TIMESTAMP(1280) 时间戳、DEVICE_ID(798) 设备号。
--           事件唯一 ID 放在串内，断网补传时原样带回，云端按该 ID 幂等即可去重。
--   · 本地：/sd/log/cabinet_event_YYYYMMDD.csv（不受 enabled 影响，始终写，掉电不丢）
--   照片上传由下面的 upload_photo 单独控制（走文件上传通道，与事件通道互不影响）。
--   字段名必须落在固件 FIELD_MEANINGS 内：OPERATION_TYPE/BOX_NUMBER/PASSWORD/
--      PACKAGE_SIZE 这些官方表里没有（取到 nil），会让 TLV 构造失败，故统一使用上面的标准字段。
--   开关：这里写 true 就是 true、写 false 就是 false（config.get 只在取值为 nil 时才回退默认值）。
config.report = {
    enabled = true,              -- 事件是否上传云平台（false=只写本地 CSV；照片上传不受此开关影响）
    upload_photo = true,         -- 照片是否上传云平台（仅刷脸场景有照片：FACE_STORE / FACE_PICKUP）
    local_log_dir = "/sd/log",   -- 本地流水目录（SD 未挂载自动回退 /ram/log，注意 /ram 掉电丢）
    local_log_keep_days = 30,    -- 本地流水保留天数（0=不自动清理）
    -- 关箱判定（锁控板 81 主动上报 + 定时轮询读状态兜底）
    box_close = {
        poll_interval = 5,       -- 轮询读锁状态间隔(s)，0=不轮询（只依赖锁板主动上报）
        timeout = 60,            -- 开箱后多久没收到"门关闭"就按超时估算一条关箱事件(s)，0=不估算
    },
    -- 照片上传队列（异步，不阻塞业务；失败重试次数）
    photo_retry = 2,
    -- 断网补传：事件/照片先落本地队列，联网后自动补录云端（掉电不丢）
    pending = {
        file = "/sd/log/pending_upload.jsonl", -- 补传队列文件（SD 未挂载自动回退 /ram/log 同名文件）
        max_items = 500,     -- 队列条数上限（超出丢最旧，防止写满存储）
        retry_interval = 30, -- 联网后补传轮询间隔(s)；收到云平台连接成功事件还会立刻补一次
    },
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
-- ★ 注意不能写成 `value or default`：配置项值若为布尔 false（例如 config.report.enabled = false），
--   `value or default` 会把它顶成 default（true）→ 开关永远关不掉（现象是 config 里写了 false，
--   设备仍打印"事件上云=true"并真的在上报）。
--   只有"取不到（nil）"时才回退默认值。
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
    if value == nil then
        return default
    end
    return value
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
    
    -- 无配置文件时使用默认值（如需读配置文件，可在此补充加载逻辑）
end

-- 导出配置模块
return config
