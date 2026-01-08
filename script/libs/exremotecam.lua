--[[
@module exremotecam
@summary exremotecam 远程摄像头控制扩展库，提供统一的摄像头OSD文字显示设置和拍照功能API。
@version 1.0
@date    2025.12.29
@author  拓毅恒
@usage
   用法实例
   注意：
        1. exremotecam.lua支持控制不同品牌的网络摄像头，提供统一的OSD文字显示设置和拍照功能API
        2. 使用前需要先加载具体品牌的摄像头功能模块，然后再加载exremotecam主模块
        3. 使用前请确保网络连接正常，能够访问到目标摄像头

    使用exremotecam库时，需要按照以下顺序加载模块：
        local dhcam = require "dhcam" -- 首先加载具体型号的摄像头功能模块（如大华dhcam）
        local exremotecam = require "exremotecam" -- 然后加载exremotecam主模块


local dhcam = require "dhcam"
local exremotecam = require "exremotecam"

-- OSD文字显示参数配置表
local osd_param = {
    brand = "dhcam",  -- 摄像头品牌，当前仅支持"dhcam"(大华)
    host = "192.168.1.108",  -- 摄像头/NVR的IP地址
    channel = 0,  -- 摄像头通道号
    text = "行1|行2|行3",  -- OSD文本内容，需用竖线分隔，格式如"1111|2222|3333|4444"
    x = 0,  -- 显示位置的X坐标
    y = 2000  -- 显示位置的Y坐标
}

-- 拍照功能参数配置表
local photo_param = {
    brand = "dhcam",  -- 摄像头品牌，当前仅支持"dhcam"(大华)
    host = "192.168.1.108",  -- 摄像头/NVR的IP地址
    channel = 0  -- 摄像头通道号
}

function camera_start()
    sys.waitUntil("WIFI_CONNECT_OK") -- 等待网络连接成功
    
    -- 设置摄像头OSD文字显示
    log.info("开始设置OSD显示")
    exremotecam.osd(osd_param)
    
    -- 控制摄像头拍照，若SD卡可用，则图片保存为/sd/1.jpeg
    log.info("开始拍照操作")
    exremotecam.get_photo(photo_param)
    
    log.info("远程摄像头控制操作完成")
end

sys.taskInit(camera_start)
]]

local exremotecam = {}
-- 全局变量定义
local camera_id, camera_buff

--[[
设置摄像头OSD(屏幕显示)文字功能
@api exremotecam.osd(camera_param)
@table camera_param 参数表
@string camera_param.brand 摄像头品牌
@string camera_param.host 摄像头/NVR的IP地址
@number camera_param.channel 摄像头通道号（主要用于NVR）
@string camera_param.text OSD文本内容，需用竖线分隔
@number camera_param.x 显示位置的X坐标
@number camera_param.y 显示位置的Y坐标
@return boolean 返回值
 false：OSD设置失败
 true：OSD设置成功
@usage
-- 大华摄像头示例
local osd_param = {
    brand = "dhcam",
    host = "192.168.1.100",
    channel = 1,
    text = "温度: 25℃|湿度: 60%|设备ID: 001",
    x = 100,
    y = 200
}
local result = exremotecam.osd(osd_param)
log.info("osd", "设置结果: " .. result)

-- 多通道NVR示例
local osd_param = {
    brand = "dhcam",
    host = "192.168.1.100",
    channel = 3,  -- 第3通道
    text = "通道3|监控区域: 大厅|时间: " .. os.date("%Y-%m-%d %H:%M:%S"),
    x = 100,
    y = 200
}
local result = exremotecam.osd(osd_param)
log.info("osd", "设置结果: " .. result)
]]
function exremotecam.osd(camera_param)
    -- 参数类型检查
    if type(camera_param) ~= "table" then
        log.error("osd", "参数必须是table类型")
        return false
    end
    -- 检查必要参数
    if not camera_param.brand then
        log.error("osd", "缺少必要参数: brand")
        return false
    end
    if not camera_param.host then
        log.error("osd", "缺少必要参数: host")
        return false
    end
    if not camera_param.text then
        log.error("osd", "缺少必要参数: text")
        return false
    end

    local brand = camera_param.brand
    if brand == "dhcam" then
        -- 调用大华摄像头的set_osd方法
        return dhcam.set_osd({
            host = camera_param.host,
            data = camera_param.text,
            channel = camera_param.channel or 0,
            x = camera_param.x or 0,
            y = camera_param.y or 0
        })
    -- 后续可添加其他品牌的处理
    -- elseif brand == "Hikvision" then
    --     -- 调用海康威视摄像头的set_osd方法
    --     return hkcam.set_osd({
    --         host = camera_param.host,
    --         data = camera_param.text,
    --         channel = camera_param.channel or 0,
    --         x = camera_param.x or 0,
    --         y = camera_param.y or 0
    --     })
    -- elseif brand == "Uniview" then
    --     return yscam.set_osd({
    --         host = camera_param.host,
    --         data = camera_param.text,
    --         channel = camera_param.channel or 0,
    --         x = camera_param.x or 0,
    --         y = camera_param.y or 0
    --     })
    -- elseif brand == "TianDiWeiye" then
    --     return tdwycam.set_osd({
    --         host = camera_param.host,
    --         data = camera_param.text,
    --         channel = camera_param.channel or 0,
    --         x = camera_param.x or 0,
    --         y = camera_param.y or 0
    --     })
    else
        -- 处理不支持的品牌
        log.info("osd","型号填写错误或暂不支持！！！")
    end
end

--[[
控制摄像头拍照功能
@api exremotecam.get_photo(camera_param)
@table camera_param 参数表
@string camera_param.brand 摄像头品牌
@string camera_param.host 摄像头/NVR的IP地址
@number camera_param.channel 摄像头通道号（主要用于NVR）
@return number 返回值
 0：拍照失败
 1：拍照成功，并且照片保存到/sd/1.jpeg
 2：拍照成功，但是照片没有保存本地
@usage
-- 大华摄像头示例
local photo_param = {
    brand = "dhcam",
    host = "192.168.1.100",
    channel = 0
}
local result = exremotecam.get_photo(photo_param)
log.info("get_photo", "拍照结果: " .. result)

-- 多通道NVR示例
local photo_param = {
    brand = "dhcam",
    host = "192.168.1.100",
    channel = 2  -- 第2通道
}
local result = exremotecam.get_photo(photo_param)
log.info("get_photo", "拍照结果: " .. result)
]]
function exremotecam.get_photo(camera_param)
    -- 参数类型检查
    if type(camera_param) ~= "table" then
        log.error("get_photo", "参数必须是table类型")
        return 0
    end
    -- 检查必要参数
    if not camera_param.brand then
        log.error("get_photo", "缺少必要参数: brand")
        return 0
    end
    if not camera_param.host then
        log.error("get_photo", "缺少必要参数: host")
        return 0
    end

    local brand = camera_param.brand
    if brand == "dhcam" then
        -- 调用大华摄像头的take_picture方法
        return dhcam.take_picture({
            host = camera_param.host,
            channel = camera_param.channel or 0
        })
    -- 后续可添加其他品牌的处理
    -- elseif brand == "Hikvision" then
    --     -- 调用海康威视摄像头的take_picture方法
    --     return hkcam.take_picture({
    --         host = camera_param.host,
    --         channel = camera_param.channel or 0
    --     })
    -- elseif brand == "Uniview" then
    --     return yscam.take_picture({
    --         host = camera_param.host,
    --         channel = camera_param.channel or 0
    --     })
    -- elseif brand == "TianDiWeiye" then
    --     return tdwycam.take_picture({
    --         host = camera_param.host,
    --         channel = camera_param.channel or 0
    --     })
    else
        -- 处理不支持的品牌
        log.info("get_photo","型号填写错误或暂不支持！！！")
    end
end

return exremotecam