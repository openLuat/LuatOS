--[[
@module  airlink_net
@summary Airlink SPI初始化 + WiFi AP + Web配置服务器
@version 2.0
@date    2026.09.14
@author  江访
@usage
参考exremotefile的create_ap流程，SPI替代UART
--]]

--============================================================
-- Airlink SPI 引脚配置
--============================================================
local SPI_ID      = 0
local SPI_CS_PIN  = 8
local SPI_RDY_PIN = 33
local SPI_IRQ_PIN = 24
local SPI_SPEED   = 8 * 1000000
local WIFI_RST    = 32

local AP_IP       = "192.168.4.1"
local HTTP_PORT   = 80
local HTML_FILE   = "/luadb/config_page.html"

--============================================================
-- 模块
--============================================================
local M = {}
local cfg = nil
dnsproxy = require("dnsproxy")
dhcpsrv  = require("dhcpsrv")

--============================================================
-- HTML配置页面
--============================================================
local function read_html_file()
    local f = io.open(HTML_FILE, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function build_html(template, ssid, password, baudrate, msg)
    local page = template
    page = string.gsub(page, "{{SSID}}", ssid or "")
    page = string.gsub(page, "{{PASSWORD}}", password or "")
    local baud = tonumber(baudrate) or 115200
    local rates = {"9600", "19200", "38400", "57600", "115200", "230400", "460800", "921600"}
    for _, r in ipairs(rates) do
        if tonumber(r) == baud then
            page = string.gsub(page, 'value="' .. r .. '"', 'value="' .. r .. '" selected')
        end
    end
    if msg and msg ~= "" then
        local cls = string.find(msg, "成功") and "ok" or "err"
        page = string.gsub(page, "{{MSG}}", "<p class='" .. cls .. "'>" .. msg .. "</p>")
    else
        page = string.gsub(page, "{{MSG}}", "")
    end
    return page
end

--============================================================
-- HTTP处理
--============================================================
local function url_decode_char(hex)
    return string.char(tonumber(hex, 16))
end

local function parse_form(body)
    local params = {}
    if not body or body == "" then return params end
    for k, v in string.gmatch(body, "([^&=]+)=([^&]*)") do
        v = string.gsub(v, "%%(%x%x)", url_decode_char)
        params[k] = v
    end
    return params
end

local function http_handler(method, path, body)
    if not cfg then cfg = require "config" end
    if method == "GET" and path == "/config" then
        local t = read_html_file()
        if not t then return "500", "text/plain", "HTML not found" end
        return "200", "text/html", build_html(t, cfg.get("ssid",""), cfg.get("password",""), cfg.get("baudrate",115200), nil)
    elseif method == "POST" and path == "/config" then
        local t = read_html_file()
        if not t then return "500", "text/plain", "HTML not found" end
        local p = parse_form(body)
        local s = p.ssid or ""
        local pw = p.password or ""
        local br = tonumber(p.baudrate) or 115200
        if #s == 0 then
            return "200", "text/html", build_html(t, s, pw, br, "WiFi名称不能为空")
        end
        if #s > 32 then
            return "200", "text/html", build_html(t, s, pw, br, "WiFi名称不能超过32个字符")
        end
        cfg.set("ssid", s)
        cfg.set("password", pw)
        cfg.set("baudrate", br)
        log.info("airlink_net", "配置已更新", "ssid=" .. s, "baudrate=" .. br)
        return "200", "text/html", build_html(t, s, pw, br, "配置成功，重启后生效")
    end
    return "404", "text/plain", "Not Found"
end

--============================================================
-- HTTP服务器
--============================================================
local function http_server_task()
    local server = socket.create(nil, "http_server")
    if not server then
        log.info("airlink_net", "创建socket失败")
        return
    end
    socket.config(server, socket.LWIP_AP, nil, "tcp_server")
    local ok = socket.listen(server, HTTP_PORT)
    if not ok then
        log.info("airlink_net", "监听端口" .. HTTP_PORT .. "失败")
        socket.close(server)
        return
    end
    log.info("airlink_net", "Web服务器已启动 http://" .. AP_IP .. "/config")
    while true do
        local client = socket.accept(server, "http_client", 15000)
        if client then
            socket.rxpoll(client)
            local data = socket.rx(client, 4096)
            socket.noclosetx(client)
            if data and #data > 0 then
                local req_line = string.match(data, "([^\r\n]+)")
                local method, path = string.match(req_line, "(%u+)%s+(%S+)")
                local body = nil
                local bs = string.find(data, "\r\n\r\n")
                if bs then body = string.sub(data, bs + 4) end
                local status, ct, content = http_handler(method, path, body)
                socket.tx(client, "HTTP/1.1 " .. status .. " OK\r\nContent-Type: " .. ct .. "; charset=utf-8\r\nConnection: close\r\nContent-Length: " .. #content .. "\r\n\r\n" .. content)
            end
            socket.close(client)
        end
    end
end

--============================================================
-- Airlink SPI初始化（参照exremotefile的init_air6205_airlink）
--============================================================
local function init_airlink_spi()
    log.info("airlink_net", "初始化Airlink SPI通道")

    -- 复位WiFi模块
    if gpio then
        gpio.setup(WIFI_RST, 0)
        sys.wait(100)
        gpio.setup(WIFI_RST, 1)
        sys.wait(500)
    end

    -- 等待WiFi芯片上电
    sys.wait(2000)

    -- 配置SPI参数
    airlink.config(airlink.CONF_SPI_ID, SPI_ID)
    airlink.config(airlink.CONF_SPI_CS, SPI_CS_PIN)
    airlink.config(airlink.CONF_SPI_RDY, SPI_RDY_PIN)
    airlink.config(airlink.CONF_SPI_IRQ, SPI_IRQ_PIN)
    airlink.config(airlink.CONF_SPI_SPEED, SPI_SPEED)

    -- 初始化airlink + 注册STA和AP网卡（缺AP会导致adapter3找不到）
    airlink.init()
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP,  netdrv.WHALE)
    airlink.start(airlink.MODE_SPI_MASTER)

    sys.wait(2000)
    log.info("airlink_net", "Airlink SPI通道已建立")
end

--============================================================
-- 创建WiFi AP（完全参照exremotefile的create_ap）
--============================================================
local function create_ap(ssid, password)
    log.info("airlink_net", "创建AP热点: " .. ssid)

    -- wlan.init() + wlan.createAP() 通过airlink RPC发送到Air6205
    wlan.init()
    sys.wait(100)

    wlan.createAP(ssid, password or "")
    sys.wait(500)

    -- 等待AP网络就绪
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    log.info("airlink_net", "AP网络已就绪")

    -- 配置AP网络
    netdrv.ipv4(socket.LWIP_AP, AP_IP, "255.255.255.0", "0.0.0.0")
    log.info("airlink_net", "AP IP已配置:", AP_IP)

    -- DNS代理
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)

    -- DHCP服务器
    dhcpsrv.create({adapter = socket.LWIP_AP})
    log.info("airlink_net", "DHCP已启动")

    -- 等待AP完全广播
    sys.wait(3000)

    sys.publish("AP_CREATE_OK")
    log.info("airlink_net", "AP热点创建成功")
end

--============================================================
-- 对外接口
--============================================================
function M.setup(ssid, password)
    if not airlink then
        log.info("airlink_net", "airlink库不存在")
        return false
    end
    if not wlan then
        log.info("airlink_net", "wlan库不存在")
        return false
    end

    -- 步骤1：初始化airlink SPI通道
    init_airlink_spi()

    -- 步骤2：创建WiFi AP
    create_ap(ssid, password)

    -- 步骤3：启动Web配置服务器
    sys.taskInit(http_server_task)

    return true
end

return M
