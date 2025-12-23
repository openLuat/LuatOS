--[[
@module  update
@summary 远程升级功能模块
@version 1.0
@date    2025.08.12
@author  孟伟
@usage
实现远程升级功能，具体流程如下：
1、判断网卡是否连接成功；
2、初始化fota2模块；
3、配置fota2模块的参数；
4、调用fota2模块的升级函数；
5、在升级结果的回调函数中，根据升级结果进行处理；
]]
-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id

libfota2 = require "libfota2"



-- 循环打印版本号, 方便看版本号变化, 非必须
function get_version()
    log.info("降功耗 找合宙")
    log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())
end
sys.timerLoopStart(get_version, 3000)


-- 升级结果的回调函数
-- 功能:获取fota的回调函数
-- 参数:
-- result:number类型
--   0表示成功
--   1表示连接失败
--   2表示url错误
--   3表示服务器断开
--   4表示接收报文错误
--   5表示使用iot平台VERSION需要使用 xxx.yyy.zzz形式
local function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        log.info("升级包下载成功,重启模块")
        rtos.reboot()
    elseif ret == 1 then
        log.info("连接失败", "请检查url拼写或服务器配置(是否为内网)")
    elseif ret == 2 then
        log.info("url错误", "检查url拼写")
    elseif ret == 3 then
        log.info("服务器断开", "检查服务器白名单配置")
    elseif ret == 4 then
        log.error("FOTA 失败",
            "原因可能有：\n" ..
            "1) 服务器返回 200/206 但报文体为空(0 字节）—— 通常是升级包文件缺失或 URL 指向空文件；\n" ..
            "2) 服务器返回 4xx/5xx 等异常状态码 —— 请确认升级包已上传、URL 正确、鉴权信息有效；\n"..
            "3) 已经是最新版本，无需升级" )
    elseif ret == 5 then
        log.info("版本号书写错误", "iot平台版本号需要使用xxx.yyy.zzz形式")
    else
        log.info("不是上面几种情况 ret为", ret)
    end
end

-- 使用合宙iot平台进行升级, 支持自定义参数, 也可以不配置，如果要配置参数可以参考此链接https://docs.openluat.com/osapi/ext/libfota2/
local ota_opts = {}

function fota_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("fota_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("fota_task_func", "recv IP_READY", socket.dft())

    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    if "123" == _G.PRODUCT_KEY  then
        while 1 do
            sys.wait(1000)
            log.info("fota", "请修改正确的PRODUCT_KEY")
        end
    end

    log.info("开始检查升级")
    libfota2.request(fota_cb, ota_opts)
end

--创建并且启动一个task
--运行这个task的主函数fota_task_func
sys.taskInit(fota_task_func)
-- 演示定时自动升级, 每隔4小时自动检查一次
sys.timerLoopStart(libfota2.request, 4 * 3600000, fota_cb, ota_opts)


