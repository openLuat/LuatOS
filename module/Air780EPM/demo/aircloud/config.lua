--[[
@module  config
@summary 全局业务配置
@version 1.1.0
@date    2026.08.29
@author  LuatOS 嵌入式软件设计开发
@usage
本文件集中管理 excloud 云平台通信示例工程的全局业务配置。
其他业务模块通过 require("config") 获取本配置表，便于统一修改、集中维护。

本示例默认以「4G 主控」设备身份接入 AirCloud 云平台，
excloud 库会自动根据模组型号识别设备类型为 1（4G主控）。
如果需要在 PC 模拟器上以「虚拟设备」方式调试，可将下方 config.force_virtual_device
设为 true 并手动填写 virtual_phone_number/virtual_serial_num。

【关于以下配置项的说明】
本文件以「官方 excloud 扩展库」实际支持的配置参数为准（参见 excloud.lua 内的 config 表）。
凡官方支持、但本示例默认不打算启用（保持官方默认值）的字段，均已在此列出并附注释，
仅用于说明其作用与用法，方便开发者按需开启——即「仅补充、不实际使用」。

【配置项分类说明（重要）】
本配置表包含两类配置项，请注意区分：
  1) excloud.setup() 入参（未特别标注的配置项）：
     即 excloud 扩展库 config 表支持的参数（传输协议、服务器地址、鉴权、MQTT 参数、
     SSL 证书、重连策略、debug、mtn_log_enabled / mtn_log_blocks / mtn_log_write_way
     / aircloud_mtn_log_enabled 等），会在 excloud.setup() 执行时逐项写入库内部配置。
  2) 业务层配置（非 setup 入参，注释中均标注【业务层配置·非 setup 入参】）：
     由本工程的业务模块（excloud_main / excloud_report / excloud_upload）直接读取使用，
     不会传给 excloud.setup()。例如心跳间隔/心跳数据、业务上报周期、日志 TAG、
     运维日志自动上传开关与周期等。请勿误以为这些是 excloud.setup() 的参数。
]]-- 导入 excloud 库，用于读取其提供的常量（DATA_TYPES / FIELD_MEANINGS 等）
-- 注意：这里仅为获取常量使用，真正的服务初始化放在 excloud_main 模块中
local excloud = require("excloud")

-- 全局配置表（供其它模块引用）
local config = {
    -- =========================================================================
    -- 一、核心设备属性（一般无需手动配置，此处仅作说明）
    -- =========================================================================
    -- device_type     设备类型：1=4G主控 2=WiFi主控 3=MCU主控 9=虚拟设备
    --                 由 excloud.setup() 内部 get_device_type() 根据模组型号自动识别。
    --                 若手动传入 setup()，库会打印告警并忽略，故不在此处设置。
    -- device_id       设备 ID（自动获取）：4G 取 IMEI、WiFi 取 MAC、MCU 取唯一 ID。
    --                 由 excloud.setup() 自动获取，无需手动配置。
    -- protocol_version 协议版本号（库已固定为 2，手动传入 setup() 会告警并忽略，故不设置）。
    -- 上面三项均由 excloud 库自动处理，请勿在下方重复配置。

    -- =========================================================================
    -- 二、传输协议选择
    -- =========================================================================
    -- 接入 AirCloud 支持三种传输协议，这里通过 config.transport 统一指定：
    --   "tcp"  —— 基于 TCP socket 的长连接（默认，最常用）
    --   "udp"  —— 基于 UDP socket 的连接（需配合 udp_auth_key 鉴权密钥）
    --   "mqtt" —— 基于 MQTT 协议的连接（可配置 qos/retain/keepalive 等）
    -- 切换协议时，只需修改这里的 transport 值，并同步维护下方对应的协议参数即可。
    transport = "tcp",
    -- SSL/TLS 加密开关（全局生效，同时控制 TCP 与 MQTT 通道，默认 false）
    -- 【官方平台（合宙 AirCloud）】
    --   TCP/UDP 承载为明文端口：必须保持 false，误设为 true 会走 TLS 握手导致连接失败。
    --   MQTT 承载需要加密传输：切换 transport="mqtt" 时请设为 true（见下方第四部分说明）。
    -- 【第三方平台】按第三方服务器实际要求配置：明文端口保持 false，TLS 端口设为 true。
    ssl = false,

    -- =========================================================================
    -- 三、服务器地址与鉴权参数
    -- =========================================================================
    -- use_getip = true 时，excloud 会自动调用 getip 进行服务器发现，
    -- 自动获取服务器地址、端口、MQTT 用户名/密码、鉴权 key、UDP 密钥等接入参数
    -- （推荐保持 true）。
    -- 【官方平台】默认走合宙官方 getip 服务（地址见下方 getip_url），推荐保持 true；
    -- 【第三方平台】若第三方提供兼容的 getip 服务，可修改 getip_url 指向其地址；
    --   否则关闭 use_getip，手动配置 host / port / auth_key 等接入参数。
    --
    -- 【通用规则：手动配置优先，getip 绝不覆盖】getip 只在某个字段“尚未被手动配置（为 nil）”
    -- 时，才会用服务器返回的值去回填。凡是下面这些连接/鉴权相关字段中你已手动填写过的，
    -- 一律以你填写的为准，getip 不会去覆盖它：
    --     host / port / username / password / auth_key / udp_auth_key
    -- 也就是说，这一规则并不仅限于 host/port，而是对以上所有接入参数统一生效。
    -- 因此你完全可以一边开启 use_getip 自动发现，一边按需手动指定某个字段，两者不会冲突。
    -- 若希望某个字段完全交由 getip 自动获取，保持该字段为 nil（或不填）即可。
    --
    -- 若 use_getip = false，则必须手动配置 host/port，并按需配置 auth_key 鉴权密钥。
    use_getip = true,
    -- 服务器地址（默认保持 nil，交由 getip 自动填充）
    -- 【注意】本示例默认 use_getip=true，真实服务器地址由 getip 服务器发现自动获取，
    --         因此这里应保持 nil，让 getip 把自动获取到的地址填入 host。
    --         无需（也不建议）手动指定固定的 i.openluat.com，否则会覆盖 getip 的结果。
    --         仅当 use_getip=false 改用手动接入时，才需在此手动指定服务器地址。
    host = nil,
    -- 服务器端口（默认保持 nil，交由 getip 自动填充）
    -- 用法同 host：use_getip=true 时由 getip 自动获取端口号；仅手动接入时才需指定。
    port = nil,

    -- 用户项目鉴权密钥（仅当 use_getip=false 手动接入时需要；开启 getip 时由服务器下发）
    -- 【说明】最新版 excloud 库已支持配置该字段，遵循「手动配置优先」通用规则：
    --          若手动填写，getip 不会覆盖；保持 nil 时，getip 才会用服务器返回的值回填。
    -- 【官方平台】开启 getip 时由合宙服务器自动下发 auth_key，保持 nil 即可。
    -- 【第三方平台】若关闭 getip 改用手动接入，且第三方服务器要求鉴权密钥时，才需手动设置：
    --   use_getip = false,
    --   host = "xxx",
    --   port = 1883,
    --   auth_key = "your_project_auth_key",
    auth_key = nil,

    -- UDP 鉴权密钥（仅 transport="udp" 时必填）
    -- 该密钥用于 UDP 模式下拼接在报文尾部，防止伪造；TCP/MQTT 模式无需配置。
    udp_auth_key = nil,

    -- 是否优先使用 IPv6（false=优先 IPv4，true=优先 IPv6）
    ipv6 = false,
    -- getip 服务器发现服务的请求地址（一般无需修改）
    getip_url = "https://api.luatos.com/iot/getip",

    -- =========================================================================
    -- 四、MQTT 专用参数（仅 transport="mqtt" 时生效）
    -- =========================================================================
    qos = 0,                -- MQTT QoS 等级：0/1/2
    retain = 0,             -- MQTT retain 标志：0/1
    clean_session = true,   -- MQTT clean session 标志
    keepalive = 300,        -- MQTT 心跳间隔（秒）
    -- 【SSL 说明】合宙官方平台的 MQTT 通信承载需要加密传输（ssl=true）：
    --   使用官方平台 MQTT 时，请将上方"二、传输协议选择"中的 config.ssl 配置为 true，
    --   并按需配置下方第六部分的 server_cert / client_cert / client_key 等证书参数。
    --   若接入第三方平台，则以第三方服务器要求为准：明文端口 ssl=false，TLS 端口 ssl=true。
    -- 本示例默认 transport="tcp"，ssl 保持 false 即可，此处不再单独定义 ssl 字段。
    -- MQTT 客户端标识/用户名/密码（可选；不填则按设备自动生成，见 excloud.open()）
    -- 若手动填写，则优先于自动生成值与 getip 回填值，不会被覆盖。
    client_id = nil,        -- MQTT 客户端标识（可选，不填则为 IMEI/MAC/唯一ID）
    username = nil,         -- MQTT 用户名（可选，不填则等于 client_id）
    password = nil,         -- MQTT 密码（可选，不填则为 MUID 或空）
    -- MQTT 主题（不填则使用 excloud 默认主题）
    mqtt_pub_auth_topic = nil,  -- 鉴权发布主题，默认 /AirCloud/up/{设备标识}/auth
    mqtt_pub_data_topic = nil,  -- 数据发布主题，默认 /AirCloud/up/{设备标识}/all
    mqtt_sub_auth_topic = nil,  -- 鉴权订阅主题，默认 /AirCloud/down/{设备标识}/auth
    mqtt_sub_data_topic = nil,  -- 数据订阅主题，默认 /AirCloud/down/{设备标识}/all

    -- =========================================================================
    -- 五、getip 文件上传来源（图片 / 音频 / 运维日志）
    -- =========================================================================
    -- 这三个参数分别控制「图片 / 音频 / 运维日志」三类文件上传时，是否采用
    -- 【合宙平台】的上传参数，而不再依赖 getip 服务器发现返回的上传地址与凭据。
    --
    -- 作用与默认值：
    --   imginfo_from_luat = false  —— 图片上传默认走 getip 自动获取的上传配置
    --   audinfo_from_luat = false  —— 音频上传默认走 getip 自动获取的上传配置
    --   mtninfo_from_luat = false  —— 运维日志上传默认走 getip 自动获取的上传配置
    --
    -- 使用说明：
    --   保持默认 false 即可：use_getip=true 时，excloud 会通过 getip 拿到上传地址与凭据。
    --   若希望某类文件上传直接使用合宙平台参数（例如 use_getip=false、或 getip 未返回上传信息，
    --   或你希望固定走合宙平台），请将对应项设为 true：
    --     imginfo_from_luat = true,   -- 图片上传走合宙平台
    --     audinfo_from_luat  = true,  -- 音频上传走合宙平台
    --     mtninfo_from_luat  = true,  -- 运维日志上传走合宙平台
    -- 该开关对应 excloud 库内部 _upload_with_config() 的 from_luat 分支：为 true 时
    -- 直接调用 get_luat_upload_info() 取合宙平台上传参数，不再执行 getip。
    -- 【第三方平台】若不使用合宙平台的上传服务（如自建上传服务），保持 false 即可，
    --   上传地址与凭据由 getip 返回或自行实现上传逻辑，无需开启本开关。
    -- 【本示例保持默认 false，仅作用法说明，不实际启用】
    imginfo_from_luat = false,
    audinfo_from_luat = false,
    mtninfo_from_luat = false,

    -- =========================================================================
    -- 六、Socket 底层与 SSL 证书参数（一般无需修改，仅作说明）
    -- =========================================================================
    -- TCP/UDP socket 的底层参数，多数情况下使用默认值即可。
    local_port = nil,       -- 本地端口（nil=自动分配）
    keep_idle = nil,        -- TCP keepalive 空闲时间（秒）
    keep_interval = nil,    -- TCP keepalive 探测间隔（秒）
    keep_cnt = nil,         -- TCP keepalive 探测次数
    -- SSL/TLS 证书相关（仅当上方 config.ssl=true 时按需配置）
    -- 【官方平台】MQTT 承载使用官方服务器，一般使用库内置/系统默认信任链即可，无需手动配置。
    -- 【第三方平台】若第三方服务器要求自定义 CA 或双向认证，才需按需配置以下证书参数。
    server_cert = nil,      -- 服务器 CA 证书
    client_cert = nil,      -- 客户端证书
    client_key = nil,       -- 客户端私钥
    client_password = nil,  -- 客户端私钥口令
    -- 【本示例默认保持 nil，交由 excloud 库按官方默认值处理，不实际启用】

    -- =========================================================================
    -- 七、虚拟设备参数（仅 PC 模拟器调试时使用）
    -- =========================================================================
    -- 默认关闭：真机 4G 主控应保持 false，让 excloud 自动识别设备类型。
    -- 若在 PC 上模拟虚拟设备调试，请将下值设为 true 并正确填写手机号/序列号。
    force_virtual_device = false,
    virtual_phone_number = "13800138000", -- 虚拟设备手机号（11位）
    virtual_serial_num = 1,               -- 虚拟设备序列号（0-999）

    -- =========================================================================
    -- 八、重连策略
    -- =========================================================================
    auto_reconnect = true,      -- 是否自动重连
    reconnect_interval = 10,    -- 重连间隔（秒）
    max_reconnect = 3,          -- 最大重连次数（超限后会重新 getip）
    timeout = 30,               -- 连接超时（秒）

    -- =========================================================================
    -- 九、心跳保活
    -- =========================================================================
    -- 心跳间隔（秒）：自动心跳使用
    -- 【业务层配置·非 setup 入参】由 excloud_main 在鉴权成功后调用
    --   excloud.start_heartbeat(heartbeat_interval, heartbeat_data) 时作为第一个参数传入。
    heartbeat_interval = 300,
    -- 是否在连接/认证成功后自动启动心跳
    -- 【业务层配置·非 setup 入参】由 excloud_main 判断鉴权成功后是否调用 start_heartbeat。
    auto_start_heartbeat = true,
    -- 心跳携带的 TLV 数据（列表，默认 nil 时由 excloud_main 自动构造 TIMESTAMP 心跳）
    -- 【业务层配置·非 setup 入参】由 excloud_main 作为第二个参数传入
    --   excloud.start_heartbeat(interval, custom_data)；该参数不是 excloud.setup() 的入参。
    -- 【重要】心跳必须携带至少一个 TLV 字段，否则 excloud 库会返回
    --   "没有有效的TLV数据可发送"，心跳发送失败，服务器可能判定设备离线。
    -- 【默认行为】保持 nil 即可：excloud_main 会自动构造时间戳心跳：
    --   { { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
    --       data_type    = excloud.DATA_TYPES.INTEGER,
    --       value        = os.time() } }
    -- 【自定义】如需携带业务字段，可在此配置 TLV 列表（与上报数据格式一致），例如：
    --   heartbeat_data = {
    --       { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
    --         data_type    = excloud.DATA_TYPES.INTEGER,
    --         value        = os.time() },
    --       { field_meaning = excloud.FIELD_MEANINGS.BATTERY_LEVEL,  -- 示例：电量
    --         data_type    = excloud.DATA_TYPES.INTEGER,
    --         value        = 80 },
    --   },
    heartbeat_data = nil,

    -- =========================================================================
    -- 十、业务上报周期
    -- =========================================================================
    -- 周期上报任务：每上报_周期 秒上报一次业务数据
    -- 【业务层配置·非 setup 入参】由 excloud_report 的周期上报任务读取；
    --   该参数不是 excloud.setup() 的入参。
    report_cycle = 60,

    -- =========================================================================
    -- 十一、日志与杂项
    -- =========================================================================
    debug = false,          -- 是否开启 excloud 底层调试日志
    -- 业务日志 TAG
    -- 【业务层配置·非 setup 入参】仅用于本工程各业务模块打印日志时统一标识，
    --   不会被传入 excloud.setup()。
    log_tag = "excloud_demo", -- 业务日志 TAG

    -- 运维日志功能开关
    -- 开启后 excloud.mtn_log() 才能正常记录运维日志，且可被 upload_mtnlogs() 上传
    mtn_log_enabled = true,
    -- 运维日志每个文件的块数
    mtn_log_blocks = 1,
    -- 运维日志写入方式（excloud.MTN_LOG_CACHE_WRITE / excloud.MTN_LOG_ADD_WRITE）：
    --   excloud.MTN_LOG_CACHE_WRITE（0，缓存写）：日志先写入内存缓存，待缓存满（4KB）
    --     或文件滚动时才落盘。日志量小时缓存可能长时间不落盘，若此时上传日志文件，
    --     会出现文件不存在或大小为 0 的问题。
    --   excloud.MTN_LOG_ADD_WRITE（1，直接追加写）：每次写入直接落盘，文件大小准确，
    --     测试/排查时建议使用，避免缓存未落盘导致文件大小为 0。
    -- 【说明】excloud 库默认值为 CACHE_WRITE；本示例为便于测试上传，使用 ADD_WRITE。
    mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE,
    -- 是否启用 AirCloud 平台的运维日志（在库底层额外记录 aircloud 相关日志）
    aircloud_mtn_log_enabled = true,

    -- 周期上传运维日志开关：开启后每隔 mtn_log_upload_cycle 秒主动上传一次
    -- 【业务层配置·非 setup 入参】由 excloud_upload 的自动上传任务读取；
    --   该参数不是 excloud.setup() 的入参。
    auto_upload_mtnlog = true,
    -- 运维日志上传周期（秒）
    -- 【业务层配置·非 setup 入参】由 excloud_upload 的自动上传任务读取，
    --   配合上方 auto_upload_mtnlog 使用；该参数不是 excloud.setup() 的入参。
    mtn_log_upload_cycle = 3600, -- 运维日志上传周期（秒）
}

-- =========================================================================
-- 十二、控制命令协议说明（供 excloud_cmd 模块解析使用）
-- =========================================================================
-- 本示例中，服务器通过 CONTROL_COMMAND 字段下发的控制命令，其 value 采用
-- 【JSON 字符串】承载，顶层为【裸数组】（无 fields 外壳），一条命令可携带多条字段控制。
-- 命令报文格式示例（【按消息tag路由】）：
--   [{"field_meaning":775,"data_type":0,"value":1}]
--   [{"field_meaning":800,"data_type":0,"value":12}]
--   [{"field_meaning":775,"data_type":0,"value":1},
--    {"field_meaning":800,"data_type":0,"value":12}]
-- 其中：
--   field_meaning —— 消息tag，取值必须来自 excloud.FIELD_MEANINGS（代码里有多少就是多少，不支持自定义）
--   data_type     —— 数据类型（excloud.DATA_TYPES.*）
--   value         —— 该字段要设置的数值
-- 【防呆处理】若 value 不是合法 JSON 数组（如仅下发单个字符 "1"、纯文本、空数组等），
--   视为误下发，模组仅记录日志，不执行任何字段动作、不回传结果。
-- 【上下行属性注意（仅供理解，模组不校验）】上下行属性的识别与过滤由【平台端】负责：
--  平台在下发控制命令前会按上下行属性自动识别，只会下发“可控制”（“设备⇄平台（双向）”或
--  “仅下行（平台→设备）”）的字段。“设备→平台（纯上行）”字段（如 SIGNAL_STRENGTH_4G/GNSS_*/SIM_ICCID 等）
--  不会被平台下发为控制命令；即使出现，模组也只按普通字段处理，不做拒绝。设备端只需保证
--  field_meaning 存在于 excloud.FIELD_MEANINGS 中，无需关心上下行属性。
--  另注意：A.1 控制信令（16~255）为协议“信封”信令，不属于控制命令里可下发的业务字段。
-- 服务器下发后，模组按每条 field 的 field_meaning 逐条路由到 excloud_cmd 中注册的处理器执行，
-- 最后通过 CONTROL_RESPONSE 字段逐条回带 field_meaning + result（0=成功）。

-- 导出给其它模块使用的字段含义常量引用（避免重复 require excloud）
config.DATA_TYPES = excloud.DATA_TYPES
config.FIELD_MEANINGS = excloud.FIELD_MEANINGS

return config
