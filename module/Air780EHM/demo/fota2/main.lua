-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fotademo"
-- iot限制，只能上传xxx.yyy.zzz格式的三位数的版本号，但实际上现在只用了XXX和ZZZ,中间yyy暂未使用
-- 需要注意的是,因为yyy不生效，所以111.222.333版本和111.444.333版本，对iot平台来说都一样，所以建议中间那一位永远写000
VERSION = "001.000.000"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libfota2 = require "libfota2"

-- 联网函数, 可自行删减
sys.taskInit(function()
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    log.info("4G网络链接成功")
    sys.publish("net_ready")
end)

-- 循环打印版本号, 方便看版本号变化, 非必须
sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        log.info("降功耗 找合宙")
        -- log.info("fota", "脚本版本号", VERSION)
        log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())
    end
end)

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
        log.info("接收报文错误", "检查模块固件或升级包内文件是否正常")
    elseif ret == 5 then
        log.info("版本号书写错误", "iot平台版本号需要使用xxx.yyy.zzz形式")
    else
        log.info("不是上面几种情况 ret为", ret)
    end
end
local ota_opts = {}

-- 使用合宙iot平台进行升级,不需要管下面这段代码
-- 使用第三方服务器时打开下面这段代码
--[[local ota_opts = {
    url = "", 
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
    version = ""
    -- 其他更多参数, 请查阅libfota2的文档 https://wiki.luatos.com/api/libs/libfota2.html
}]]--
sys.taskInit(function()
    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    if "123" == _G.PRODUCT_KEY and not ota_opts.url then
        while 1 do
            sys.wait(1000)
            log.info("fota", "请修改正确的PRODUCT_KEY")
        end
    end
    -- 等待网络就行后开始检查升级
    sys.waitUntil("net_ready")
    log.info("开始检查升级")
    sys.wait(500)
    libfota2.request(fota_cb, ota_opts)
end)
-- 演示定时自动升级, 每隔4小时自动检查一次
sys.timerLoopStart(libfota2.request, 4 * 3600000, fota_cb, ota_opts)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
