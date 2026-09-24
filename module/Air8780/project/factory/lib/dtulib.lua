dtulib={}
--- 软件重启
-- @string r 重启原因，用户自定义，一般是string类型，重启后的trace中会打印出此重启原因
-- @return 无
-- @usage sys.restart('程序超时软件重启')
function dtulib.restart(r)
    assert(r and r ~= "", "sys.restart cause null")
    log.warn("sys.restart",r)
    -- mobile.flymode(0, true)--重启前进入下飞行模式，避免重启前上次模块和基站的心跳没断导致下次驻网不上
    -- mobile.flymode(1, true)
    rtos.reboot()
end
--- table.merge(...) 合并多个表格
-- @table[...],要合并的多个table
-- @return table,返回合并后的表格
-- @usage table.merge({1,2,3},{3, a = 4, b = 5, 6})
function dtulib.merge(...)
    local tabs = {...}
    if #tabs == 0 then return {} end
    local origin = tabs[1]
    for i = 2, #tabs do
        if origin then
            if tabs[i] then
                for k, v in pairs(tabs[i]) do
                    if type(k) == "number" then
                        table.insert(origin, v)
                    else
                        origin[k] = v
                    end
                end
            end
        else
            origin = tabs[i]
        end
    end
    return origin
end


local Content_type = {'application/x-www-form-urlencoded', 'application/json', 'application/octet-stream'}

--- 返回utf8编码字符串的单个utf8字符的table
-- @string str，utf8编码的字符串,支持中文
-- @return table,utf8字符串的table
-- @usage local t = string.utf8ToTable("中国2018")
function utf8ToTable(str)
    local tab = {}
    for uchar in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
        tab[#tab + 1] = uchar
    end
    return tab
end

--- 返回字符串的urlEncode编码
-- @string str，要转换编码的字符串,支持UTF8编码中文
-- @return str,urlEncode编码的字符串
-- @usage local str = string.urlEncode("####133") ,str == "%23%23%23%23133"
-- @usage local str = string.urlEncode("中国2018") , str == "%e4%b8%ad%e5%9b%bd2018"
function urlEncode(str)
    local t = utf8ToTable(str)
    for i = 1, #t do
        if #t[i] == 1 then
            t[i] = string.gsub(string.gsub(t[i], "([^%w_%*%.%- ])", function(c) return string.format("%%%02X", string.byte(c)) end), " ", "+")
        else
            t[i] = string.gsub(t[i], ".", function(c) return string.format("%%%02X", string.byte(c)) end)
        end
    end
    return table.concat(t)
end

-- 处理表的url编码
function urlencodeTab(params)
    local msg = {}
    for k, v in pairs(params) do
        table.insert(msg,  urlEncode(k) .. '=' .. urlEncode(v))
        table.insert(msg, '&')
    end
    table.remove(msg)
    return table.concat(msg)
end

--- HTTP客户端
-- @string method,提交方式"GET" or "POST"
-- @string url,HTTP请求超链接
-- @number timeout,超时时间
-- @param params,table类型，请求发送的查询字符串，通常为键值对表
-- @param data,table类型，正文提交的body,通常为键值对、json或文件对象类似的表
-- @number ctype,Content-Type的类型(可选1,2,3),默认1:"urlencode",2:"json",3:"octet-stream"
-- @string basic,HTTP客户端的authorization basic验证的"username:password"
-- @param headers,table类型,HTTP headers部分
-- @param cert,table类型，此参数可选，默认值为： nil，ssl连接需要的证书配置，只有ssl参数为true时，才参数才有意义，cert格式如下：
-- {
--  caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--  clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--  clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式) clientPassword = "123456", --客户端证书文件密码[可选]
--  }
-- @return string,table,string,正常返回response_code, response_header, response_body
-- @return string,string,错误返回 response_code, error_message
-- @usage local c, h, b = httpv2.request(url, method, headers, body)
-- @usage local r, e  = httpv2.request("http://wrong.url/ ")
function dtulib.request(method, url, timeout, params, data, ctype, basic, head, cert, fnc)
    local _, idx, offset, ssl, auth, https, host, port, path
    local headers = {
        ['User-Agent'] = 'Mozilla/4.0',
        ['Accept'] = '*/*',
        ['Accept-Language'] = 'zh-CN,zh,cn',
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ['Connection'] = 'close',
    }
    if type(head) == "string" then
        -- log.info("user header:", basic, head)
        local tmp = {}
        for k, v in string.gmatch(head, "(.-):%s*(.-)\r\n") do tmp[k] = v end
        -- headers = tmp
        dtulib.merge(headers, tmp)
    elseif type(head) == "table" then
        dtulib.merge(headers, head)
    end
 

    _, idx, auth = url:find("(.-:.-)@", (offset or 0) + 1)
    offset = idx or offset
    -- 处理HTTP协议body部分的数据
    ctype = ctype or 2
    headers['Content-Type'] = Content_type[ctype]
    if ctype == 1 and type(data) == 'table' then
        data = urlencodeTab(data)    
    elseif ctype == 2 and data ~= nil then
        data = type(data) == 'string' and data or (type(data) == 'table' and json.encode(data)) or ""
    elseif ctype == 3 and type(data) == 'string' then
        headers['Content-Length'] = io.fileSize(data) or 0
    elseif data and type(data) == "string" then
        headers['Content-Length'] = #data or 0
    end
    -- 处理HTTP Basic Authorization 验证
    if auth then
        headers['Authorization'] = 'Basic ' .. crypto.base64_encode(auth, #auth)
    elseif type(basic) == 'string' and basic ~= "" then
        headers['Authorization'] = 'Basic ' .. crypto.base64_encode(basic, #basic)
    end
    -- 处理headers部分
    local str = ""
    for k, v in pairs(headers) do str = str .. k .. ": " .. v .. "\r\n" end

    -- log.info("AAAA",method,url,headers,data)
    return http.request(method,url,headers,data,{timeout=timeout}).wait()
end
--- 将HEX字符串转成Lua字符串，如"313233616263"转为"123abc", 函数里加入了过滤分隔符，可以过滤掉大部分分隔符（可参见正则表达式中\s和\p的范围）。
-- @string hex,16进制组成的串
-- @return charstring,字符组成的串
-- @return len,输出字符串的长度
-- @usage
function dtulib.fromHexnew(hex)
    return hex:gsub("[%s%p]", ""):gsub("%x%x", function(c)
        return string.char(tonumber(c, 16))
    end)
end

--- 按照指定分隔符分割字符串
-- @string str 输入字符串
-- @param[opt=string,number,nil] delimiter 分隔符：
--      string: 字符串类型分隔符
--      number: 按长度分割
--      nil   ：相当于"", 将字符串转为字符数组
-- @return 分割后的字符串列表
-- @usage "123,456,789":split(',') -> {'123','456','789'}
function dtulib.split(str, delimiter)
    local strlist, tmp = {}, string.byte(delimiter)
    if delimiter and delimiter == "" then
        for i = 1, #str do strlist[i] = str:sub(i, i) end
    elseif type(delimiter) == "number" then
        for i = 1, #str, delimiter do table.insert(strlist, str:sub(i, i + delimiter - 1)) end
    else
        for substr in string.gmatch(str .. delimiter, "(.-)" .. (((tmp > 96 and tmp < 123) or (tmp > 64 and tmp < 91) or (tmp > 47 and tmp < 58)) and delimiter or "%" .. delimiter)) do
            table.insert(strlist, substr)
        end
    end
    return strlist
end
--- 将序列化的lua字符串反序列化为lua基本类型
-- @string str: 序列化后的基本类型字符串
-- @return param: 反序列化为 number or table or string or boolean
-- @usage local v = string.unSerialize("true") --> v为布尔值True
function dtulib.unSerialize(str)
    return loadstring("return " .. str) and loadstring("return " .. str)() or str
end

return dtulib