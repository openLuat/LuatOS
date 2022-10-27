--- 模块功能：Google ProtoBuffs 编解码
-- @module pb
-- @author wendal
-- @release 2022.9.8

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pbdemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(500)
    -- 如果没有这个库, 就云编译一份吧: https://wiki.luatos.com/develop/compile/Cloud_compilation.html
    if not protobuf then
        log.info("protobuf", "this demo need protobuf lib")
        return
    end
    -- 加载 pb 文件, 这个是从pbtxt 转换得到的
    -- 下载资源到模块时不需要下载pbtxt
    -- 转换命令: protoc.exe -operson.pb --cpp_out=cpp person.pbtxt
    -- protoc.exe 下载地址: https://github.com/protocolbuffers/protobuf/releases
    protobuf.load(io.readFile("/luadb/person.pb"))
    local tb = {
        name = "wendal",
        id = 123,
        email = "abc@qq.com"
    }
    while 1 do
        sys.wait(1000)
        -- 用 protobuf 编码数据
        local pbdata = protobuf.encode("Person", tb)
        if pbdata then
            -- 打印数据长度. 编码后的数据含不可见字符, toHex是方便显示
            log.info("protobuf", "encode",  #pbdata, (pbdata:toHex()))
        end
        -- 用 json 编码数据, 用于对比大小
        local jdata = json.encode(tb)
        if jdata then
            log.info("json", #jdata, jdata)
        end
        -- 可见 protobuffs 比 json 节省很多空间

        -- 后续是演示解码
        local re = protobuf.decode("Person", pbdata)
        if re then
            -- 打印数据, 因为table不能直接显示, 这里转成json来显示
            log.info("protobuf", "decode", json.encode(re))
        end
    end
end)

-- 主循环, 必须加
sys.run()
