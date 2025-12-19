--[[
@module  psm+_power_fota
@summary psm+超低功耗模式下升级功能模块
@version 1.0
@date    2025.08.12
@author  孟伟
@usage
本文件为psm+超低功耗模式下升级功能模块，核心设计思路
1.升级触发机制 ：
   - 定时器唤醒升级 ：设备定期从PSM模式唤醒，主动检查是否有新固件版本。
   - 外部中断唤醒升级 ：通过特定GPIO中断或网络消息唤醒设备进行升级。
2.防止升级过程中进入休眠 ：
   - 在开始FOTA升级前，禁用PSM模式进入。
   - 升级完成后，根据结果决定是否重启设备或重新进入PSM模式。

]]
-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id
--加在libfota2扩展库
libfota2 = require "libfota2"


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
    --升级结束，触发升级回调，发布消息升级结束，可以进入休眠模式
    sys.publish("FOTA_END")
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
local opts = {
    url = "###http://cdn.openluat-backend.openluat.com/upgrade_firmware/fotademo_2008.001.001_LuatOS-SoC_Air8000.bin_20250623184110381812",
    -- 合宙IOT平台的默认升级URL, 不填就是这个默认值
    -- 如果是自建的OTA服务器, 则需要填写正确的URL, 例如 http://192.168.1.5:8000/update
    -- 如果自建OTA服务器,且url包含全部参数,不需要额外添加参数, 请在url前面添加 ###
    -- 如果不加###，则默认会上传如下参数
    -- 1. opts.version string 版本号, 默认是 BSP版本号.x.z格式
    -- 2. opts.timeout int 请求超时时间, 默认300000毫秒,单位毫秒
    -- 3. opts.project_key string 合宙IOT平台的项目key, 默认取全局变量PRODUCT_KEY. 自建服务器不用填
    -- 4. opts.imei string 设备识别码, 默认取IMEI(Cat.1模块)或WLAN MAC地址(wifi模块)或MCU唯一ID
    -- 5. opts.firmware_name string 底层版本号

    -- 请求的版本号, 合宙IOT有一套版本号体系,不传就是合宙规则, 自建服务器的话当然是自行约定版本号了
    -- version = ""
    -- 其他更多参数, 请查阅libfota2的文档 https://wiki.luatos.com/api/libs/libfota2.html
}


function psm_fota_task_func()
    -- 如果是被定时器唤醒，因为上次进入PSM+时是开启了飞行模式，所以在唤醒后第一时间关闭飞行模式。
    mobile.flymode(0, false)
    log.info("开始测试PSM+模式功耗。")

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

    log.info("开始检查升级")
    libfota2.request(fota_cb, opts)

    -- 打印版本号, 方便看版本号变化, 非必须
    log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())


    -- 等待下载升级包结束, 发布消息"FOTA_END",
    -- 如果15秒内没有收到消息，则15秒的时长到达后进入PSM+模式。
    -- 需要注意的是在fota_cb回调函数中，升级包下载成功后，会立马重启并升级模组。如果还有其他事情要做不想立马重启升级,需自行决定reboot的时机
    -- 升级包下载成功后，本demo默认是立即自动重启并且将升级包更新到模组中，更新成功后，会再次走到这里
    -- 再次走到这里后，合宙iot平台会返回“已经是最新版本，不需要升级”，fota_cb回调函数中会发布消息"FOTA_END"
    -- 至此，才会继续向下执行代码，进入PSM+模式
    sys.waitUntil("FOTA_END", 15000)

    log.info("升级结束,进入PSM模式")


    -- 定时检查升级 (每4小时唤醒一次)
    pm.dtimerStart(2, 4 * 3600000)
    -- 启动飞行模式，规避可能会出现的网络问题
    mobile.flymode(0, true)
    -- 进入PSM模式
    pm.power(pm.WORK_MODE, 3)
    -- 防御机制：15秒后如果未进入PSM则重启
    sys.wait(15000)
    log.info("进入PSM+失败,重启")
    rtos.reboot()
end

sys.taskInit(psm_fota_task_func)
