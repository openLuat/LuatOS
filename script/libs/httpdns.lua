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
    local code, _, body = http.request("GET", "http://119.29.29.29/d?dn=" .. tostring(n), nil, nil, opts).wait()
    if code == 200 and body and #body > 2 then
        local tmp = body:split(",")
        if tmp then return tmp[1] end
    end
end

return httpdns


