--[[
@module  iotauth_app
@summary 物联网平台 MQTT 三元组参数生成功能模块
@version 1.0
@date    2025.10.31
@author  马梦阳
@usage
本功能模块演示的内容为：
利用 iotauth 库为各主流物联网平台生成 MQTT 连接所需的 client_id、user_name、password 参数：
1. 为 阿里云 生成 MQTT 三元组参数
2. 为 中移OneNet 生成 MQTT 三元组参数
3. 为 华为云IoTDA 生成 MQTT 三元组参数
4. 为 腾讯云 生成 MQTT 三元组参数
5. 为 涂鸦云 生成 MQTT 三元组参数
6. 为 百度云 生成 MQTT 三元组参数

注意事项：
1. iotauth 库及该示例代码仅供参考，目前已不再提供维护和技术支持服务
2. 该示例代码存放于：https://gitee.com/openLuat/LuatOS/tree/master/olddemo/iotauth
3. 在烧录底层固件时需要选择支持 64 位的固件版本
    Air7xxx、Air8000 系列模组选择版本号为 101-199 的固件
    Air8101 系列模组选择版本号为 V2xxx 的固件（目前 V2xxx 版本固件还没有第一版）

本文件没有对外接口,直接在 main.lua 中 require "iotauth_app" 就可以加载运行；
]]

-- 阿里云 MQTT 三元组参数生成
local function generate_aliyun_auth()
    local client_id, user_name, password = iotauth.aliyun(
        "a1B2c3D4e5F",
        "sensor_001",
        "Y877Bgo8X5owd3lcB5wWDjryNPoB",
        "hmacsha256",
        324721152001213,
        true
    )
    log.info("aliyun", client_id, user_name, password)
end

-- 中移OneNet MQTT 三元组参数生成
local function generate_onenet_auth()
    local client_id, user_name, password = iotauth.onenet(
        "Ck2AF9QD2K",
        "test",
        "T0s3ZkJEdkIxTnR6YktZRXRZMFpKTnNGblpycGdidFY=",
        "sha256",
        32472115200,
        "2048-10-31"
    )
    log.info("onenet", client_id, user_name, password)
end

-- 华为云 IoTDA MQTT 三元组参数生成
local function generate_iotda_auth()
    local client_id, user_name, password = iotauth.iotda(
        "6203cc94c7fb24029b110408_88888888",
        "123456789"
    )
    log.info("iotda", client_id, user_name, password)
end

-- 腾讯云 MQTT 三元组参数生成
local function generate_qcloud_auth()
    local client_id, user_name, password = iotauth.qcloud(
        "LD8S5J1L07",
        "test",
        "acyv3QDJrRa0fW5UE58KnQ==",
        "sha256",
        32472115200,
        "12010126"
    )
    log.info("qcloud", client_id, user_name, password)
end

-- 涂鸦云 MQTT 三元组参数生成
local function generate_tuya_auth()
    local client_id, user_name, password = iotauth.tuya(
        "6c95875d0f5ba69607nzfl",
        "fb803786602df760",
        7258089600
    )
    log.info("tuya", client_id, user_name, password)
end

-- 百度云 MQTT 三元组参数生成
local function generate_baidu_auth()
    local client_id, user_name, password = iotauth.baidu(
        "abcd123",
        "mydevice",
        "ImSeCrEt0I1M2jkl",
        "SHA256",
        32472115200
    )
    log.info("baidu", client_id, user_name, password)
end

-- 主任务函数
local function main_task()
    -- 生成阿里云 MQTT 三元组参数
    generate_aliyun_auth()
    -- 生成中移OneNet MQTT 三元组参数
    generate_onenet_auth()
    -- 生成华为云 IoTDA MQTT 三元组参数
    generate_iotda_auth()
    -- 生成腾讯云 MQTT 三元组参数
    generate_qcloud_auth()
    -- 生成涂鸦云 MQTT 三元组参数
    generate_tuya_auth()
    -- 生成百度云 MQTT 三元组参数
    generate_baidu_auth()
end

-- 启动任务
sys.taskInit(main_task)
