--[[
@module  fskv_test
@summary fskv_test测试功能模块
@version 1.0
@date    2025.11.14
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EHM/EHV/EGH核心板演示fskv核心库API的用法，演示设置kv数据、设置 table 内的键值对数据，用kv迭代器遍历kv数据，删除kv数据等操作。

运行核心逻辑：
1.初始化fskv
2.获取 kv 数据库状态
3.设置不同类型的kv数据
4.设置 table 内的键值对数据
5.根据 key 获取对应的数据
6.使用kv迭代器遍历kv数据
7.删除kv数据，清空KV数据

]]
--1.定义功能函数：置kv 数据
local function setKV()
    --如下所示设置用户数据是字符串
    local r1 = fskv.set("my_str", "goodgoodstudy")
    log.info("fskv设置用户数据是字符串", r1)
    --如下所示设置用户数据是布尔值
    local r2 = fskv.set("my_bool", true)
    log.info("fskv设置用户数据是布尔值", r2)
    --如下所示设置用户数据是数值
    local r3 = fskv.set("my_number", 1.23)
    log.info("fskv设置用户数据是数值", r3)
    --如下所示设置用户数据是整数
    local r4 = fskv.set("my_int", 5)
    log.info("fskv设置用户数据是整数", r4)
    --如下所示设置用户数据是table
    local r5 = fskv.set("my_table", { name = "wendal", age = 18 })
    log.info("fskv用户数据是table类型", r5)

   return true
end


--2.定义功能函数：设置 table 内的键值对数据
local function setttable()
    --如下所示设置用户数据是字符串
    local r1=fskv.sett("mytable", "wendal", "goodgoodstudy")
    log.info("mytable设置用户数据是字符串", r1)
    --如下所示设置用户数据是布尔值
    local r2=fskv.sett("mytable", "upgrade", true)
    log.info("mytable设置用户数据是布尔值", r2)
    --如下所示设置用户数据是数值
    local r3=fskv.sett("mytable", "timer", 1)
    log.info("mytable设置用户数据是数值", r3)
    --如下所示设置用户数据是table
    local r4=fskv.sett("mytable", "bigd", { name = "wendal", age = 123 })
    log.info("mytable设置用户数据是table", r4)
    return true
end

--3.定义功能函数：获取kv数据
local function getKV()
    local my_str = fskv.get("my_str")
    log.info("获取my_str的类型和值", type(my_str), my_str)
    local my_bool = fskv.get("my_bool")
    log.info("获取upgrade的类型和值", type(my_bool), my_bool)
    local my_number = fskv.get("my_number")
    log.info("获取my_number的类型和值", type(my_number), my_number)
    local my_int = fskv.get("my_int")
    log.info("获取my_int的类型和值", type(my_int), my_int)
    local my_table = fskv.get("my_table")
    log.info("获取my_table的类型和值", my_table,json.encode(my_table))

    local mytable = fskv.get("mytable")
    log.info("获取mytable的类型和值", mytable, json.encode(mytable))
    return true
end

--4.定义功能函数：kv数据库迭代器遍历KV数据
local function iterKV()
    local iter = fskv.iter()
    log.info("kv数据库迭代器", iter)
    if iter then
        while 1 do
            local k = fskv.next(iter)
            log.info("kv迭代器获取下一个key", k)
            if not k then
                log.info("kv数据库遍历完成")
                break
            end
            log.info("fskv", k, "value", fskv.get(k))
        end
    end
    return true
end
--====功能演示主函数====
local function fskv_test()
    -- 初始化kv数据库
    local r = fskv.init()
    log.info("fskv", "init complete", r)

    --获取 kv 数据库状态
    local used, total, kv_count = fskv.status()
    log.info("获取kv数据库状态", "fskv", "kv", used, total, kv_count)


    --=======设置kv 数据=======
    if not setKV() then
        log.info("设置kv数据失败")
    end

    --=======设置 table 内的键值对数据=======
    if not setttable() then
        log.info("设置 table 内的键值对数据失败")
    end

    --======根据 key 获取对应的数据====
    if not getKV() then
        log.info("获取kv数据失败")
    end
    --======使用kv数据库迭代器遍历KV数据====
    if not iterKV() then
        log.info("遍历kv数据失败")
    end

    

    -- 删除测试
    local d = fskv.del("my_bool")
    log.info("fskv", "my_bool删除结果", d)
    local t = fskv.get("my_bool")
    log.info("fskv", "删除后查询my_bool", type(t), t)


    -- 如果设置table的value为nil, 代表删除对应的skey
    -- 如下写法是删除name
    log.info("设置新的table，key是mytable2", fskv.set("mytable2", { age = 18, name = "wendal" }))
    log.info("mytable2的值", fskv.get("mytable2"),json.encode(fskv.get("mytable2")))
    log.info("mytable2删除name测试", fskv.sett("mytable2", "name", nil))
    log.info("mytable2删除结果", fskv.get("mytable2"), json.encode(fskv.get("mytable2")))


    --清空整个kv数据库
    log.info("清空整个kv数据库", fskv.clear())


    local used, total, kv_count = fskv.status()
    log.info("获取kv数据库状态", "fskv", "kv", used, total, kv_count)
end

sys.taskInit(fskv_test)
