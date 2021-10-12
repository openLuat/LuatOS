--- 模块功能：参数管理
-- @module nvm
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.11.9

local nvm = {}
--实时参数配置存储在paraname文件中
--默认参数配置存储在configname文件中
--para：实时参数表
--config：默认参数表
paraname, paranamebak = "/nvm_para.lua", "/nvm_para_bak.lua"
local para, libdftconfig, configname, cconfigname, econfigname = {}

--[[
函数名：serialize
功能  ：根据不同的数据类型，按照不同的格式，写格式化后的数据到文件中
参数  ：
pout：文件句柄
o：数据
返回值：无
]]
local function serialize(pout, o)
    if type(o) == "number" then
        --number类型，直接写原始数据
        pout:write(o)
    elseif type(o) == "string" then
        --string类型，原始数据左右各加上双引号写入
        pout:write(string.format("%q", o))
    elseif type(o) == "boolean" then
        --boolean类型，转化为string写入
        pout:write(tostring(o))
    elseif type(o) == "table" then
        --table类型，加换行，大括号，中括号，双引号写入
        pout:write("{\n")
        for k, v in pairs(o) do
            pout:write(" [")
            serialize(pout, k)
            pout:write("] = ")
            serialize(pout, v)
            pout:write(",\n")
        end
        pout:write("}\n")
    else
        error("cannot serialize a " .. type(o))
    end
end

--[[
函数名：upd
功能  ：更新实时参数表
参数  ：
overide：是否用默认参数强制更新实时参数
返回值：无
]]
function nvm.upd(overide)
    for k, v in pairs(libdftconfig) do
        if k ~= "_M" and k ~= "_NAME" and k ~= "_PACKAGE" then
            if overide or para[k] == nil then
                para[k] = v
            end
        end
    end
end

local function safePcall(file)
    return pcall(require, file)
end

--[[
函数名：load
功能  ：初始化参数
参数  ：无
返回值：无
]]
local function load()
    local f, fBak, fExist, fBakExist
    f = io.open(paraname, "rb")
    fBak = io.open(paranamebak, "rb")

    if f then
        fExist = f:read("*a") ~= ""
        f:close()
    end
    if fBak then
        fBakExist = fBak:read("*a") ~= ""
        fBak:close()
    end

    print("load fExist fBakExist", fExist, fBakExist)

    local fResult, fBakResult
    if fExist then
        fResult, para = safePcall(paraname:match("/(.+)%.lua"))
    end

    print("load fResult", fResult)

    if fResult then
        os.remove(paranamebak)
        nvm.upd()
        return
    end

    if fBakExist then
        fBakResult, para = safePcall(paranamebak:match("/(.+)%.lua"))
    end

    print("load fBakResult", fBakResult)

    if fBakResult then
        os.remove(paraname)
        nvm.upd()
        return
    else
        para = {}
        nvm.restore()
    end
end

--[[
函数名：save
功能  ：保存参数文件
参数  ：
s：是否真正保存，true保存，false或者nil不保存
返回值：无
]]
local function save(s)
    if not s then return end
    local f = {}
    f.write = function(self, s)table.insert(self, s) end

    f:write("return {\n")

    for k, v in pairs(para) do
        if k ~= "_M" and k ~= "_NAME" and k ~= "_PACKAGE" then
            f:write(string.format("[%q] = ", k))
            serialize(f, v)
            f:write(",\n")
        end
    end

    f:write("}\n")

    local fparabak = io.open(paranamebak, 'wb')
    fparabak:write(table.concat(f))
    fparabak:close()

    os.remove(paraname)
    os.rename(paranamebak, paraname)
end

--- 初始化参数存储管理模块
-- @string defaultCfgFile 默认参数文件名
-- @return nil
-- @usage
-- 初始化参数存储管理模块，默认参数文件名为config.lua，本地烧录时清除已有的参数：
-- nvm.init("config.lua")
function nvm.init(defaultCfgFile)
    local f
    f, libdftconfig = safePcall(defaultCfgFile:match("(.+)%.lua"))
    configname, cconfigname, econfigname = "/"..defaultCfgFile, "/"..defaultCfgFile .. "c", "/"..defaultCfgFile .. "e"

    --初始化配置文件，从文件中把参数读取到内存中
    load()
end

--- 设置某个参数的值
-- @string k 参数名
-- @param v，可以是任意类型，参数的新值
-- @param r，设置原因，如果传入了非nil的有效参数，并且v值和旧值相比发生了改变，
--                     会产生一个PARA_CHANGED_IND内部消息，携带 k,v,r 3个参数
-- @param s，是否立即写入到文件系统中，false不写入，其余的都写入
-- @return bool或者nil，成功返回true，失败返回nil
-- @usage
-- 参数name赋值为Luat，立即写入文件系统：
-- nvm.set("name","Luat")
--
-- 参数age赋值为12，立即写入文件系统：
-- 如果旧值不是12，会产生一个PARA_CHANGED_IND消息，携带 "age",12,"SVR" 3个参数：
-- nvm.set("age",12,"SVR")
--
-- 参数class赋值为Class2，不写入文件系统：
-- nvm.set("class","Class2",nil,false)
--
-- 参数score赋值为{chinese=100,math=99,english=98}，立即写入文件系统：
-- nvm.set("score",{chinese=100,math=99,english=98})
--
-- 连续写入4个参数，前3个不保存到文件系统中，写第4个时，一次性全部保存到文件系统中：
-- nvm.set("para1",1,nil,false)
-- nvm.set("para2",2,nil,false)
-- nvm.set("para3",3,nil,false)
-- nvm.set("para4",4)
function nvm.set(k, v, r, s)
    local bchg = true
    if type(v) ~= "table" then
        bchg = (para[k] ~= v)
    end
    log.info("nvm.set", bchg, k, v, r, s)
    if bchg then
        para[k] = v
        save(s or s == nil)
        if r then sys.publish("PARA_CHANGED_IND", k, v, r) end
    end
    return true
end

--- 设置某个table类型参数的某一个索引的值
-- @string k table类型的参数名
-- @param kk table类型参数的某一个索引名
-- @param v，table类型参数的某一个索引的新值
-- @param r，设置原因，如果传入了非nil的有效参数，并且v值和旧值相比发生了改变，会产生一个TPARA_CHANGED_IND消息，携带 k,kk,v,r 4个参数
-- @param s，是否立即写入到文件系统中，false不写入，其余的都写入
-- @return bool或者nil，成功返回true，失败返回nil
-- @usage nvm.sett("score","chinese",100)，参数score["chinese"]赋值为100，立即写入文件系统
-- @usage nvm.sett("score","chinese",100,"SVR")，参数score["chinese"]赋值为100，立即写入文件系统，
-- 如果旧值不是100，会产生一个TPARA_CHANGED_IND消息，携带 "score","chinese",100,"SVR" 4个参数
-- @usage nvm.sett("score","chinese",100,nil,false)，参数class赋值为Class2，不写入文件系统
function nvm.sett(k, kk, v, r, s)
    local bchg = true
    if type(v) ~= "table" then
        bchg = (para[k][kk] ~= v)
    end
    if bchg then
        para[k][kk] = v
        save(s or s == nil)
        if r then sys.publish("TPARA_CHANGED_IND", k, kk, v, r) end
    end
    return true
end

--- 所有参数立即写入文件系统
-- @return nil
-- @usage nvm.flush()
function nvm.flush()
    save(true)
end

--- 读取某个参数的值
-- @string k 参数名
-- @return 参数值
-- @usage
-- 读取参数名为name的参数值：
-- nameValue = nvm.get("name")
function nvm.get(k)
    return para[k]
end

--- 读取某个table类型参数的键名对应的值
-- @string k table类型的参数名
-- @param kk table类型参数的键名
-- @usage
-- 有一个table参数为score，数据如下：
-- score = {chinese=100, math=100, english=95}
-- 读取score中chinese对应的值：
-- nvm.gett("score","chinese")
function nvm.gett(k, kk)
    return para[k][kk]
end

--- 参数恢复出厂设置
-- @return nil
-- @usage nvm.restore()
function nvm.restore()
    os.remove(paraname)
    os.remove(paranamebak)
    local fpara, fconfig = io.open(paraname, "wb"), io.open(configname, "rb")
    if not fconfig then fconfig = io.open(cconfigname, "rb") end
    if not fconfig then fconfig = io.open(econfigname, "rb") end
    fpara:write(fconfig:read("*a"))
    fpara:close()
    fconfig:close()
    nvm.upd(true)
end

--- 请求删除参数文件.
-- 此接口一般用在远程升级时，需要用新的config.lua覆盖原来的参数文件的场景，在此场景下，远程升级包下载成功后，在确定要重启前调用此接口
-- 下次开机执行nvm.init("config.lua")时，会用新的config.lua文件自动覆盖参数文件；以后再开机就不会自动覆盖了
-- 也就是说"nvm.remove()->重启->nvm.init("config.lua")"是一个仅执行一次的完整操作
-- @return nil
-- @usage nvm.remove()
function nvm.remove()
    os.remove(paraname)
    os.remove(paranamebak)
end

return nvm
