default = {}

require "libnet"
local libfota2=require"libfota2"
local db=require "db"
local dtulib=require "dtulib"

local lbsLoc = require("lbsLoc")


-- 判断模块类型
local ver = rtos.bsp():upper()

-- 定时采集任务的初始时间
local startTime = {0, 0, 0}
-- 定时采集任务缓冲区
local sendBuff = {{}, {}, {}, {}}
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
    pins = {"", "", ""}, -- 用户自定义IO: netled,netready,rstcnf,
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

default.pios = {
    pio1 = gpio.setup(1, nil, gpio.PULLDOWN),
    pio2 = gpio.setup(2, nil, gpio.PULLDOWN),
    pio3 = gpio.setup(3, nil, gpio.PULLDOWN),
    pio4 = gpio.setup(4, nil, gpio.PULLDOWN),
    pio5 =gpio.setup(5, nil,gpio.PULLDOWN),
    pio6 =gpio.setup(6, nil,gpio.PULLDOWN),
    pio7 =gpio.setup(7, nil,gpio.PULLDOWN),
    pio8 =gpio.setup(8, nil,gpio.PULLDOWN),
    pio9 =gpio.setup(9, nil,gpio.PULLDOWN),
    pio10 =gpio.setup(10, nil,gpio.PULLDOWN),
    pio11 =gpio.setup(11, nil,gpio.PULLDOWN),
    pio16 =gpio.setup(16, nil,gpio.PULLDOWN),
    pio17 =gpio.setup(17, nil,gpio.PULLDOWN),
    pio20 =gpio.setup(20, nil,gpio.PULLDOWN),
    pio21 =gpio.setup(21, nil,gpio.PULLDOWN),
    pio22 =gpio.setup(22, nil,gpio.PULLDOWN),
    -- pio23 =gpio.setup(23, nil,gpio.PULLDOWN),
    -- pio24 =gpio.setup(24, nil,gpio.PULLDOWN),
    -- pio25 =gpio.setup(25, nil,gpio.PULLDOWN),
    pio26 =gpio.setup(26, nil,gpio.PULLDOWN),  --READY指示灯
    pio27 =gpio.setup(27, nil,gpio.PULLDOWN),  --NET指示灯
    pio28 =gpio.setup(28, nil,gpio.PULLDOWN),  
    pio29 =gpio.setup(29, nil,gpio.PULLDOWN) ,
    pio30 =gpio.setup(30, nil,gpio.PULLDOWN),
    pio31 =gpio.setup(31, nil,gpio.PULLDOWN),
    pio32 =gpio.setup(32, nil,gpio.PULLDOWN),
    pio33 =gpio.setup(33, nil,gpio.PULLDOWN),
    pio34 =gpio.setup(34, nil,gpio.PULLDOWN),
    pio35 =gpio.setup(35, nil,gpio.PULLDOWN),
    pio36 =gpio.setup(36, nil,gpio.PULLDOWN),
    pio37 =gpio.setup(37, nil,gpio.PULLDOWN),
    pio38 =gpio.setup(38, nil,gpio.PULLDOWN),
}

fskv.init()

-- 获取配置
function default.get()
    return dtu
end

-- 获取配置
function default.cfg_get()
    return cfg
end

---------------------------------------------------------- 开机读取保存的配置文件 ----------------------------------------------------------

-- NTP同步消息处理
sys.subscribe("NTP_UPDATE", function()
    local t = os.date("*t")
    log.info("网络时间已同步", string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year,t.month,t.day,t.hour,t.min,t.sec))
end)

function config_init()
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
         mobile.reqCellInfo(60)
         sys.waitUntil("CELL_INFO_UPDATE", 30000)
         log.warn("请求更新:", sys.waitUntil("UPDATE_DTU_CNF", 86400000))
     end
end


---------------------------------------------------------- 用户自定义任务初始化 ---------------------------------------------------------

function pcall_task(func)
    log.info("pcall", pcall(func))
end

function load_task()
    if dtu.task and #dtu.task ~= 0 then
        for i = 1, #dtu.task do
            if dtu.task[i] and dtu.task[i]:match("function(.+)end") then
                sys.taskInit(pcall_task,loadstring(dtu.task[i]:match("function(.+)end")))
            end
        end
    end
end

function default.init()
    log.info("config_init")
    -- 加载用户预置的配置文件
    cfg = db.new("/luadb/".. "irtu.cfg")
    local sheet = cfg:export()
    -- log.info("用户脚本文件:", cfg:export("string"))
    if type(sheet) == "table" and sheet.uconf then
        dtu = sheet
        if dtu.project_key then PRODUCT_KEY=dtu.project_key end
        if dtu.apn and dtu.apn[1] and dtu.apn[1] ~= "" then  mobile.apn(0,1,dtu.apn[1],dtu.apn[2],dtu.apn[3]) end
        if dtu.log ~= 1 then
            log.info("没有日志了哦")
            log.setLevel("SILENT") 
        end
        if dtu.isipv6==1 then
            log.info("IPV6打开了")
            mobile.ipv6(true)
        end
    end


    if dtu.pwrmod ~= "energy" then 
        pm.power(pm.WORK_MODE, 0)
    else
        pm.power(pm.WORK_MODE, 1)
    end

    if dtu.isRndis==1 then
        mobile.flymode(0, true)
        -- 设置开启RNDIS协议（bit0=1, bit1=1, bit2=0 → 0x03）
        mobile.config(mobile.CONF_USB_ETHERNET, 0x03)
        -- 退出飞行模式
        mobile.flymode(0, false)
    end
    load_task()
    sys.taskInit(config_init)
end


return default
