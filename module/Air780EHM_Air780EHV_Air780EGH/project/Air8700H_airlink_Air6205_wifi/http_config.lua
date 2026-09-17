--[[
@module  http_config
@summary Web配置服务器 - 处理HTTP请求，提供WiFi和串口参数配置页面
@version 1.0
@date    2026.09.14
@author  江访
@usage
本模块提供HTTP配置服务器功能，核心逻辑为：
1、读取HTML模板文件并填充配置数据
2、处理GET请求：返回配置页面
3、处理POST请求：保存用户配置到flash

本模块没有对外接口，在app_main.lua中通过sys.taskInit启动。
--]]

local config = require "config"

local M = {}

local HTML_FILE = "/luadb/config_page.html" -- 配置页面模板路径
local HTTP_PORT = 80                          -- HTTP服务端口

--============================================================
-- HTML模板处理
--============================================================

-- 读取HTML模板文件
local function read_html_file()
    local f = io.open(HTML_FILE, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- 将配置值填充到HTML模板的占位符中
local function build_html(template, ssid, password, baudrate, msg)
    local page = template
    -- 替换WiFi配置占位符
    page = string.gsub(page, "{{SSID}}", ssid or "")
    page = string.gsub(page, "{{PASSWORD}}", password or "")
    -- 设置波特率下拉框的选中项
    local baud = tonumber(baudrate) or 115200
    local rates = {"9600", "19200", "38400", "57600", "115200", "230400", "460800", "921600"}
    for _, r in ipairs(rates) do
        if tonumber(r) == baud then
            page = string.gsub(page, 'value="' .. r .. '"', 'value="' .. r .. '" selected')
        end
    end
    -- 显示操作结果提示
    if msg and msg ~= "" then
        local cls = string.find(msg, "成功") and "ok" or "err"
        page = string.gsub(page, "{{MSG}}", "<p class='" .. cls .. "'>" .. msg .. "</p>")
    else
        page = string.gsub(page, "{{MSG}}", "")
    end
    return page
end

--============================================================
-- HTTP请求解析
--============================================================

-- URL解码：将%XX转换为对应字符
local function url_decode_char(hex)
    return string.char(tonumber(hex, 16))
end

-- 解析POST请求体中的表单数据（key=value&key=value格式）
local function parse_form(body)
    local params = {}
    if not body or body == "" then return params end
    for k, v in string.gmatch(body, "([^&=]+)=([^&]*)") do
        v = string.gsub(v, "%%(%x%x)", url_decode_char)
        params[k] = v
    end
    return params
end

--============================================================
-- HTTP请求处理回调（供httpsrv调用）
--============================================================

local function handle_http(fd, method, uri, headers, body)
    log.info("httpsrv", method, uri)

    -- GET /config：显示配置页面
    if method == "GET" and uri == "/config" then
        local t = read_html_file()
        if t then
            local html = build_html(t, config.get("ssid",""), config.get("password",""), config.get("baudrate",115200))
            return 200, {["Content-Type"]="text/html; charset=utf-8"}, html
        end
        return 500, {}, "HTML not found"
    -- POST /config：保存用户配置
    elseif method == "POST" and uri == "/config" then
        local t = read_html_file()
        if not t then
            return 500, {}, "HTML not found"
        end
        local p = parse_form(body)
        local s, pw, br = p.ssid or "", p.password or "", tonumber(p.baudrate) or 115200
        -- 参数校验
        if #s == 0 then
            return 200, {["Content-Type"]="text/html; charset=utf-8"}, build_html(t, s, pw, br, "WiFi名称不能为空")
        elseif #s > 32 then
            return 200, {["Content-Type"]="text/html; charset=utf-8"}, build_html(t, s, pw, br, "WiFi名称不能超过32个字符")
        else
            -- 保存配置到flash
            config.set("ssid", s)
            config.set("password", pw)
            config.set("baudrate", br)
            return 200, {["Content-Type"]="text/html; charset=utf-8"}, build_html(t, s, pw, br, "配置成功，重启后生效")
        end
    end
    return 404, {}, "Not Found"
end

--============================================================
-- 启动HTTP服务器（在AP网络就绪后调用）
--============================================================

function M.start()
    -- 等待AP网络创建完成
    sys.waitUntil("AP_CREATE_OK")
    -- 启动httpsrv，绑定到AP网卡的80端口
    httpsrv.start(HTTP_PORT, handle_http, socket.LWIP_AP)
    log.info("http_config", "配置服务器已启动, 端口" .. HTTP_PORT)
    log.info("http_config", "访问地址: http://192.168.4.1/config")
end

return M
