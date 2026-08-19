--[[
@module  random_app
@summary 随机数应用功能模块
@version 1.0
@date    2026.08.19
@author  沈园园
@usage
本文件为随机数应用功能模块，核心业务逻辑为：
1、使用 crypto.trng 生成真随机数；
2、使用 math.random 生成伪随机数；
3、使用 math.randomseed 设置随机数种子。

本文件没有对外接口，直接在main.lua中require "random_app"就可以加载运行；
]]

-- 随机数任务主函数
local function random_task_func()
    sys.wait(1000)      -- 等待系统稳定，1000ms

    -- 随机数测试：设置随机数种子后，循环输出真随机数和伪随机数
    log.info("random_app", "===== [1/1] 随机数测试 =====")
    math.randomseed(os.time())  -- 使用系统时间设置随机数种子
    for i = 1, 10 do
        sys.wait(100)   -- 每次输出间隔，100ms
        log.info("crypto", "真随机数", string.unpack("I", crypto.trng(4)))  -- 生成4字节真随机数并解包为整数
        log.info("crypto", "伪随机数", math.random())       -- 无参调用，输出[0,1)之间的浮点数，不推荐
        log.info("crypto", "伪随机数", math.random(100))    -- 一个参数n，输出1-100之间的随机整数
        log.info("crypto", "伪随机数", math.random(1, 65525))  -- 两个参数n,m，输出1-65525之间的随机整数，不推荐
    end
    log.info("crypto", "ALL Done")

    log.info("random_app", "===== [演示完毕] =====")
end

-- 创建一个task，并且运行task的主函数random_task_func
sys.taskInit(random_task_func)
