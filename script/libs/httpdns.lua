--[[
@module httpdns
@summary 使用Http进行域名解析
@version 1.0
@date    2023.07.13
@author  wendal
@usage
-- 通过阿里DNS获取结果
local ip = httpdns.ali("air32.cn")
log.info("httpdns", "air32.cn", ip)

-- 通过腾讯DNS获取结果
local ip = httpdns.tx("air32.cn")
log.info("httpdns", "air32.cn", ip)

-- 版本更新说明
-- 版本号：202607021200
-- 1、更新时间：2026-07-02 12:00
-- 2、更新内容
--    新增httpdns.version()接口
--    支持httpdns库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月dd日hh时mm分发布的版本
]]

local httpdns = {}

--[[
通过阿里DNS获取结果
@api httpdns.ali(domain_name, opts)
@string 域名
@table opts 可选参数, 与http.request的opts参数一致
@return string ip地址
@usage
local ip = httpdns.ali("air32.cn")
log.info("httpdns", "air32.cn", ip)
-- 指定网络适配器
local ip = httpdns.ali("air32.cn", {adapter=socket.LWIP_STA, timeout=3000})
log.info("httpdns", "air32.cn", ip)
]]
function httpdns.ali(n, opts)
    if n == nil then return end
    if opts == nil then
        opts = {timeout=3000}
    elseif opts.timeout == nil then
        opts.timeout = 3000
    end
    local code, _, body = http.request("GET", "http://223.5.5.5/resolve?short=1&name=" .. tostring(n), nil, nil, opts).wait()
    if code == 200 and body and #body > 2 then
        local jdata = json.decode(body)
        if jdata and #jdata > 0 then
            return jdata[1]
        end
    end
end


--[[
通过腾讯DNS获取结果
@api httpdns.tx(domain_name, opts)
@string 域名
@table opts 可选参数, 与http.request的opts参数一致
@return string ip地址
@usage
local ip = httpdns.tx("air32.cn")
log.info("httpdns", "air32.cn", ip)

-- 指定网络适配器
local ip = httpdns.tx("air32.cn", {adapter=socket.LWIP_STA, timeout=3000})
log.info("httpdns", "air32.cn", ip)
]]
function httpdns.tx(n, opts)
    if n == nil then return end
    if opts == nil then
        opts = {timeout=3000}
    elseif opts.timeout == nil then
        opts.timeout = 3000
    end
    local code, _, body = http.request("GET", "http://119.29.29.29/d?dn=" .. tostring(n), nil, nil, opts).wait()
    if code == 200 and body and #body > 2 then
        local tmp = body:split(",")
        if tmp then return tmp[1] end
    end
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202606300102"
@usage
httpdns.version()
]]
function httpdns.version()
    return "202607021200"
end

log.debug("httpdns", "version -> " .. httpdns.version())

return httpdns


