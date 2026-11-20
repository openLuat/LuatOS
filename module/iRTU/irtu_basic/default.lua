--[[
@module  default
@summary irtu功能初始化模块
@version 5.0.0
@date    2026.01.27
@author  李源龙
@usage
本文件为irtu的获取配置文件、初始化等功能
]]

local default = {}

local libfota2=require"libfota2"
local db=require "db"
local dtulib=require "dtulib"

local cfg

-- 配置文件
local dtu = {
    defchan = 1, -- 默认监听通道
    host = "", -- 自定义参数服务器
    passon = 0, --透传标志位
    plate = 0, --识别码标志位
    reg = 0, -- 登陆注册包
    param_ver = 0, -- 参数版本
    flow = 0, -- 流量监控
    fota = 0, -- 远程升级
    uartReadTime = 500, -- 串口读超时
    log = 1, --日志输出
    isRndis = "0", --是否打开Rndis
    isRndis2="1",
    webProtect = "0", --是否守护全部网络通道
    isipv6="0", --ipv6是否打开
    pwrmod = "normal",
    password = "",
    protectContent={}, --守护的线路
    upprot = {}, -- 上行自定义协议
    dwprot = {}, -- 下行自定义协议
    apn = {nil, nil, nil}, -- 用户自定义APN
    cmds = {{}, {}}, -- 自动采集任务参数
    pins = {"", ""}, -- 用户自定义IO: netled,netready
    wdt = {on = 0, feed_pin = "", feed_interval = 200}, -- 外置硬件看门狗（Air153C）: 开关/喂狗引脚/喂狗周期秒
    conf = {{}, {}, {}, {}, {}, {}, {}}, -- 用户通道参数
    project_key="",
    uconf = {
        {1, 115200, 8, 1,  uart.None,1,18,0},
        -- {1, 115200, 8, 1,  uart.None},
        -- {1, 115200, 8, 1,  uart.None},
        -- {3, 115200, 8, 1,  uart.None},
    }, -- 串口配置表
    gps = {
        on=0,
        fun = {2, 115200, 5, 0, 1, 1, 1,{rmc= false, gga= false, vtg= false, custom= true,custom_data= ""}, 0}, -- 串口,波特率，上报间隔，打开gps的时间,定位成功之后是否关闭gps, 采集方式，,上报通道,上报内容，震动触发采集间隔时间
    },
    task = {}, -- 用户自定义任务列表
}

--GPIO初始化输入，根据不同型号配置
-- 只定义配置结构，不在外部直接初始化GPIO
local model_gpio_configs = {
    ["Air8000A"] = {
        pins = {1, 2, 3, 4, 5, 16, 17, 20, 21, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 140, 141, 146, 147, 152, 153, 156, 160, 162, 164}
    },
    ["Air8000W"] = {
        pins = {1, 2, 3, 4, 5, 6, 7, 16, 17, 20, 21, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 140, 141, 146, 147, 152, 153, 156, 160, 162, 164}
    },
    ["Air8000D"] = {
        pins = {1, 2, 3, 4, 5, 8, 9, 10, 11, 16, 17, 20, 21, 22, 23, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38}
    },
    ["Air780EPM_Air780EHM"] = {
        pins = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38}
    },
    ["Air780EHV"] = {
        pins = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38}
    },
    ["Air780EGH_Air780EGP_Air780EGG"] = {
        pins = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 17, 20, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38}
    },
}

-- 获取当前设备型号
local function get_device_model()
    return hmeta.model()
end

-- hmeta.model() 可能上报带硬件版本后缀的型号(如 Air8000U_A14)，先去掉 "_xxx" 再按型号族匹配
local function model_base_name(model)
    if not model or model == "" then return "" end
    return (model:gsub("_.*$", ""))
end

-- 根据型号获取对应的GPIO配置
local function get_gpio_config()
    local model = get_device_model()
    local name = model_base_name(model)
    log.info("Current device model:", model)

    -- Air8000 系列子型号按是否内置 WiFi/BLE 芯片分三组：
    --   A 组(带 WiFi)：Air8000 / Air8000A / Air8000AB / Air8000U / Air8000N / Air8000XB / Air8000G
    --     SPI0 是 4G 与 WiFi 协处理器之间的 AirLink 总线：CS=GPIO8、CLK/MOSI/MISO=GPIO9~11，
    --     且 GPIO22/23 是 AirLink 的 RDY/WiFi 使能脚。这些脚绝不能初始化为普通 GPIO，
    --     否则 AirLink 会立刻断链，产测 AT+STEST=1 表现为 5 秒后返回 +CME ERROR: 100。
    --   W 组(带 WiFi)：Air8000W / Air8000WU / Air8000WN，同上，但 GPIO6/7/24/25 可用。
    --   D 组(无 WiFi)：Air8000D / Air8000DB，GPIO8~11、22/23 可作普通 IO。
    local config = nil
    if name == "Air8000T" then
        -- Air8000T 无 WiFi，沿用原有配置
        config = model_gpio_configs["Air8000A"]
    elseif name == "Air8000W" or name == "Air8000WU" or name == "Air8000WN" then
        config = model_gpio_configs["Air8000W"]
    elseif name == "Air8000D" or name == "Air8000DB" then
        config = model_gpio_configs["Air8000D"]
    elseif name == "Air8000G" then
        -- Air8000G 内置 GNSS，可用 GPIO 与 Air8000A 同集
        config = model_gpio_configs["Air8000A"]
    elseif name == "Air8000" or name == "Air8000A" or name == "Air8000U"
        or name == "Air8000N" or name == "Air8000AB" or name == "Air8000XB" then
        -- 与 Air8000A 引脚体系一致，不能将 GPIO8~11 初始化为普通输入
        config = model_gpio_configs["Air8000A"]
    elseif name == "Air780EPM" or name == "Air780EHM" then
        config = model_gpio_configs["Air780EPM_Air780EHM"]
    elseif name == "Air780EHV" then
        config = model_gpio_configs["Air780EHV"]
    elseif name == "Air780EGH" or name == "Air780EGP" or name == "Air780EGG" then
        config = model_gpio_configs["Air780EGH_Air780EGP_Air780EGG"]
    elseif name:sub(1, 7) == "Air8000" then
        -- 未列出的 Air8000 子型号统一按“带 AirLink 的 SPI0 平台”处理，
        -- 绝不能回落到包含 GPIO8~11/22/23 的 Air780EPM 表
        log.warn("Unknown Air8000 model:", model, "using Air8000A configuration")
        config = model_gpio_configs["Air8000A"]
    else
        log.warn("Unknown device model:", model, "using Air780EPM/Air780EHM default configuration")
        config = model_gpio_configs["Air780EPM_Air780EHM"] -- 默认使用Air780EPM/Air780EHM配置
    end
    
    -- 在函数内部动态初始化GPIO
    local gpio_config = {}
    for _, pin in ipairs(config.pins) do
        local pio_name = "pio" .. pin
        gpio_config[pio_name] = gpio.setup(pin, nil, gpio.PULLDOWN)
    end
    
    return gpio_config
end

-- 初始化GPIO配置
default.pios = get_gpio_config()

--初始化fskv区域
fskv.init()

-- 获取dtu配置
function default.get()
    return dtu
end

-- 获取cfg配置
function default.cfg_get()
    return cfg
end

-- NTP同步消息处理
sys.subscribe("NTP_UPDATE", function()
    local t = os.date("*t")
    log.info("网络时间已同步", string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year,t.month,t.day,t.hour,t.min,t.sec))
end)

--获取dtu配置
local function config_init()
    local rst, code, head, body, url = false
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
    --  log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
     -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
     -- 或者等待1秒超时退出阻塞等待状态;
     -- 注意：此处的1000毫秒超时不要修改的更长；
     -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
     -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
     -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
     sys.waitUntil("IP_READY", 1000)
     end

     while true do
         rst = false
         log.info("Source",dtu.source)
         if dtu.source~="uart" then
            url = "https://iot.openluat.com/api/dtu/device/" .. mobile.imei() .. "/param?product_name=" .. _G.PROJECT .. "&param_ver=" .. dtu.param_ver.."&iccid="..mobile.iccid()
            log.info("MUID",mobile.muid())
            code, head, body = dtulib.request("GET", url,30000,nil,nil,1,mobile.imei()..":"..mobile.muid())
            if tonumber(code) == 200 and body then
                log.info("Parameters issued from the server:", body)
                local dat, res, err = json.decode(body)
                if dat.code==0 then
                    local databody=json.encode(dat.parameter)
                    if res and tonumber(dat.param_ver) ~= tonumber(dtu.param_ver) then
                        _G.PRODUCT_KEY=dat.parameter.project_key
                        cfg:import(databody)
                        rst = true
                    end
                elseif dat.code==1 then
                    log.info("没有新参数。已是最新参数")
                elseif dat.code==2 then
                    log.info("未付费，登录")
                end
            else
                log.info("COde",code,body,head)
            end
        end
         -- 检查是否有更新程序
         if tonumber(dtu.fota) == 1 then
             log.info("----- update firmware:", "start!")
             libfota2.request(function(result)
                 log.info("OTA", result)
                 if result == 0 then
                     log.info("ota", "succuss")
                     -- TODO 重启
                 end
                 sys.publish("IRTU_UPDATE_RES", result == 0)
             end)
             local res, val = sys.waitUntil("IRTU_UPDATE_RES")
             rst = rst or val
             log.info("----- update firmware:", "end!")
         end
         if rst then dtulib.restart("DTU Parameters or firmware are updated!")  end
         ---------- 启动网络任务 ----------
         log.info("走到这里了")
         sys.publish("DTU_PARAM_READY")
         --进行ntp同步
         socket.sntp()
         log.warn("请求更新:", sys.waitUntil("UPDATE_DTU_CNF", 86400000))
     end
end


-- 自定义任务执行函数
function pcall_task(func)
    log.info("pcall", pcall(func))
end

-- 自定义任务执行函数
function load_task()
    if dtu.task and #dtu.task ~= 0 then
        for i = 1, #dtu.task do
            if dtu.task[i] and dtu.task[i]:match("function(.+)end") then
                sys.taskInit(pcall_task,loadstring(dtu.task[i]:match("function(.+)end")))
            end
        end
    end
end

--初始化default功能，加载模块存储在文件区的配置，然后赋值给dtu的表里面
function default.init()
    log.info("config_init")
    -- 加载用户预置的配置文件
    cfg = db.new("/luadb/".. "irtu.cfg")
    local sheet = cfg:export()
    -- log.info("用户脚本文件:", cfg:export("string"))
    if type(sheet) == "table" and sheet.uconf then
        dtu = sheet
        --把key值赋值给PRODUCT_KEY，用于后续OTA
        if dtu.project_key then PRODUCT_KEY=dtu.project_key end
        -- 如果有配置apn，则设置apn
        if dtu.apn and dtu.apn[1] and dtu.apn[1] ~= "" then  mobile.apn(0,1,dtu.apn[1],dtu.apn[2],dtu.apn[3]) end
        --如果日志等级不为1，则关闭日志
        if dtu.log ~= 1 then
            log.info("没有日志了哦")
            log.setLevel("SILENT") 
        end
        --如果配置了ipv6，则打开ipv6
        if dtu.isipv6==1 then
            log.info("IPV6打开了")
            mobile.ipv6(true)
        end
    end

    --如果配置了功耗模式，则设置功耗模式1，关于功耗问题可以参考https://docs.openluat.com/air780epm/luatos/app/lowpower/sleep/
    log.info("功耗模式",dtu.pwrmod)
    if dtu.pwrmod == "noraml" then 
        pm.power(pm.WORK_MODE, 0)
    elseif dtu.pwrmod == "energy" then
        pm.power(pm.WORK_MODE, 1)
    elseif dtu.pwrmod == "psm" then
        if dtu.psm_wakeup and dtu.psm_wakeup~="disable" then
            local last_char = string.sub(dtu.psm_wakeup, -1)
            -- 映射wakeup数字到GPIO唤醒引脚
            local wakeup_pins = {
                ["0"] = gpio.WAKEUP0,
                ["1"] = gpio.WAKEUP1,
                ["2"] = gpio.WAKEUP2,
                ["3"] = gpio.WAKEUP3,
                ["4"] = gpio.WAKEUP4,
                ["5"] = gpio.WAKEUP5,
                ["6"] = gpio.WAKEUP6,
                ["y"] = gpio.PWR_KEY
            }
            local pin = wakeup_pins[last_char]
            if pin then
                gpio.debounce(pin, 100)
                -- 定义中断回调函数
                local function wakeup_callback()
                    log.info("gpio", "wakeup"..last_char.." interrupt triggered")
                end
                -- 设置中断
                gpio.setup(pin, wakeup_callback)
                log.info("PSM唤醒中断", "已设置wakeup"..last_char.."中断")
            end
        end


    end

    -- 如果配置了RNDIS，则打开RNDIS
    if dtu.isRndis==1 then
        mobile.flymode(0, true)
        -- 设置开启RNDIS协议（bit0=1, bit1=1, bit2=0 → 0x03）
        mobile.config(mobile.CONF_USB_ETHERNET, 0x03)
        -- 退出飞行模式
        mobile.flymode(0, false)
    end
    --加载自定义任务函数
    load_task()
    --获取dtu配置和OTA功能
    sys.taskInit(config_init)
end


return default
