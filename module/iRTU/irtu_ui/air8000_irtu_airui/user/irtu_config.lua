local config = {}

local db = require "db" -- kv数据库
local dtulib = require "dtulib" -- 网络库
local libfota2 = require "libfota2" -- 固件更新库

-- 默认配置
local dtu = {
    defchan = 1,    -- 默认通道
    host = "",      -- 主机地址
    passon = 0,     -- 透传模式
    plate = 0,      -- 板卡类型
    reg = 0,        -- 注册类型
    param_ver = 0,  -- 参数版本
    flow = 0,       -- 流量类型
    fota = 0,       -- 固件更新
    uartReadTime = 500, -- 串口读取时间
    log = 1,        -- 日志级别
    isRndis = "0",  -- 是否启用RNDIS
    isRndis2 = "1", -- 是否启用RNDIS2
    webProtect = "0", -- 是否启用Web保护
    isipv6 = "0",   -- 是否启用IPv6
    pwrmod = "normal", -- 电源模式
    password = "",   -- 密码
    protectContent = {}, -- 保护内容
    upprot = {},        -- 上行协议
    dwprot = {},        -- 下行协议
    apn = {nil, nil, nil},
    cmds = {{}, {}},    -- 命令
    pins = {"", "", ""},
    conf = {{}, {}, {}, {}, {}, {}, {}},
    project_key = "",   -- 项目key
    uconf = {
        {1, 115200, 8, 1, uart.None, 1, 18, 0},
    },                  -- 串口配置
    gps = {
        fun = {"", "115200", "0", "5", "1", "json", "100", ";", "60"},
        pio = {""},
    },                  -- GPS配置
    task = {},          -- 任务
}

local cfg
local ready = false
local callbacks = {}

-- 通知回调
local function notify()
    for _, cb in ipairs(callbacks) do
        pcall(cb, dtu)
    end
end

-- 更新项目key
local function updateProductKey()
    if dtu.project_key and dtu.project_key ~= "" then
        PRODUCT_KEY = dtu.project_key
    end
end

-- 应用配置
local function applySheet(sheet)
    if type(sheet) == "table" and sheet.uconf then
        dtu = sheet
        updateProductKey()
        if dtu.apn and dtu.apn[1] and dtu.apn[1] ~= "" then
            mobile.flymode(0, true)
            mobile.apn(0, 1, dtu.apn[1], dtu.apn[2], dtu.apn[3])
            mobile.flymode(0, false)
        end
        notify()
    end
end

-- 获取远程参数
local function fetchRemoteParameters()
    local rst = false
    local url = "https://iot.openluat.com/api/dtu/device/" .. mobile.imei() ..
        "/param?product_name=" .. _G.PROJECT .. "&param_ver=" .. dtu.param_ver .. "&iccid=" .. mobile.iccid()
    log.info("MUID", mobile.muid())
    local code, head, body = dtulib.request("GET", url, 30000, nil, nil, 1, mobile.imei() .. ":" .. mobile.muid())
    if tonumber(code) == 200 and body then
        log.info("Parameters issued from the server:", body)
        local dat = json.decode(body)
        if dat and dat.code == 0 and dat.parameter then
            local databody = json.encode(dat.parameter)
            if tonumber(dat.param_ver) ~= tonumber(dtu.param_ver) then
                _G.PRODUCT_KEY = dat.parameter.project_key
                cfg:import(databody)
                applySheet(cfg:export())
                rst = true
            end
        elseif dat.code == 1 then
            log.info("没有新参数。已是最新参数")
        elseif dat.code == 2 then
            log.info("未付费，登录")
        end
    else
        log.info("Code", code, body, head)
    end
    if tonumber(dtu.fota) == 1 then
        log.info("----- update firmware:", "start!")
        libfota2.request(function(result)
            log.info("OTA", result)
            if result == 0 then
                log.info("ota", "success")
            end
            sys.publish("IRTU_UPDATE_RES", result == 0)
        end)
        local res, val = sys.waitUntil("IRTU_UPDATE_RES")
        rst = rst or val
        log.info("----- update firmware:", "end!")
    end
    if rst then
        dtulib.restart("DTU Parameters or firmware are updated!")
    end
end

-- 运行远程循环
local function runRemoteLoop()
    while true do
        -- 等待网络就绪 
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        -- 获取远程参数
        fetchRemoteParameters()
        -- 发布网络就绪事件
        sys.publish("DTU_PARAM_READY")
        ready = true
        -- 通知回调
        notify()
        -- 同步网络时间
        socket.sntp()
        -- 请求基站信息
        mobile.reqCellInfo(60)
        -- 等待基站信息更新
        sys.waitUntil("CELL_INFO_UPDATE", 30000)
        -- 请求更新配置
        log.warn("请求更新:", sys.waitUntil("UPDATE_DTU_CNF", 86400000))
    end
end

-- 获取配置
function config.get()
    return dtu
end

-- 更新回调
function config.onUpdate(cb)
    if type(cb) == "function" then
        table.insert(callbacks, cb)
    end
end

-- 是否准备好
function config.isReady()
    return ready
end

-- 初始化
function config.init()
    -- 初始化数据库
    cfg = db.new("/luadb/" .. "irtu.cfg")
    -- 导出配置
    local sheet = cfg:export()
    -- 应用配置
    applySheet(sheet)
    -- 启动远程循环
    sys.taskInit(runRemoteLoop)
end

-- 保存配置
function config.save()
    if cfg then
        cfg:import(dtu)
    end
end

-- 导出配置
function config.export(format)
    if cfg then
        return cfg:export(format)
    end
end

return config

