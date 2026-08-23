--[[
@module  face_demo
@summary Air1601/Air1602 + AirCAMERA_1032 USB摄像头 + AirCAMERA_1034摄像头人脸识别模组 人脸录入/验证应用模块
@version 2.1
@date    2026.07.30
@author  王城钧
@usage
本demo主要使用Air1601 + AirCAMERA_1032 USB摄像头 + AirCAMERA_1034摄像头人脸识别模组完成以下功能：
1、初始化USB主机模式，连接USB摄像头（AirCAMERA_1032）；
2、通过UART2（115200/8N1）与AirCAMERA_1034摄像头人脸识别模组通信；
3、查询模组固件版本、列出已注册用户、清空已有用户；
4、录入用户（register）；
5、验证用户（verify）。

接线：Air1601 UART2 TX/RX → 人脸模组 RX/TX（115200/8N1）；
前置：main.lua 中 require "face_demo"（注释掉其他业务模块）。

本文件没有对外接口，直接在main.lua中require "face_demo" 即可加载运行。
]]

local TAG = "face_demo"
local exfacecam = require "exfacecam"

log.info(TAG, "人脸识别demo启动")

-- 12号GPIO配置（AirCAMERA_1032摄像头供电控制引脚），需要拉高使能
gpio.setup(12, 1, gpio.PULLUP)

-- ======== 配置参数 ========
local CAM_W = 1280
local CAM_H = 720
local VERIFY_TIMEOUT = 15

-- ======== 实时人脸状态回调 (录入/验证过程中持续触发) ========
local function onFaceState(state, left, top, right, bottom, yaw, pitch, roll)
    local state_name = ({
        [0] = "正常", [1] = "无人脸", [2] = "偏上", [3] = "偏下",
        [4] = "偏左", [5] = "偏右", [6] = "太远", [7] = "太近",
        [8] = "眉毛遮挡", [9] = "眼睛遮挡", [10] = "面部遮挡",
        [11] = "角度异常"
    })[state] or ("未知:" .. state)
    if state ~= 1 then
        log.info(TAG, string.format("人脸[%s] 框(%d,%d,%d,%d) 姿态yaw=%d pitch=%d roll=%d",
            state_name, left, top, right, bottom, yaw, pitch, roll))
    else
        log.info(TAG, "请正对摄像头")
    end
end

-- ======== 录入用户 ========
local function doRegister(name, is_admin)
    log.info(TAG, "开始录入:", name, is_admin and "(管理员)" or "")
    local ok, user_id = exfacecam.register({
        name = name,
        admin = is_admin and 1 or 0,
        timeout = 15,
        on_state = onFaceState,
    })
    if ok then
        log.info(TAG, string.format("录入成功! user_id=%d, name=%s", user_id or -1, name))
        return user_id
    else
        log.error(TAG, "录入失败, 错误码:", user_id)
        return nil
    end
end

-- ======== 验证用户 ========
local function doVerify()
    log.info(TAG, "开始验证, 请正对摄像头...")
    local ok, result = exfacecam.verify({
        timeout = VERIFY_TIMEOUT,
        on_state = onFaceState,
    })
    if ok and result and result.user_id then
        log.info(TAG, string.format("验证成功! user_id=%d name=%s admin=%d status=%d",
            result.user_id, result.name, result.admin, result.unlock_status))
        return result
    elseif ok then
        log.info(TAG, "验证通过但无用户数据")
    else
        log.error(TAG, "验证失败, 错误:", result or "unknown")
    end
    return nil
end

-- ======== 列出所有用户 ========
local function doListUsers()
    local ok, count, ids = exfacecam.list()
    if ok then
        log.info(TAG, string.format("共%d个用户:", count))
        for i, id in ipairs(ids) do
            local ok2, info = exfacecam.query(id)
            if ok2 then
                log.info(TAG, string.format("  [%d] id=%d name=%s admin=%d", i, id, info.name, info.admin))
            else
                log.info(TAG, string.format("  [%d] id=%d", i, id))
            end
        end
        return ids
    else
        log.warn(TAG, "获取用户列表失败")
        return {}
    end
end

-- ======== 主流程 ========
local function mainTask()
    -- 启动延时，给USB摄像头/人脸模组等外部硬件上电稳定留出时间
    sys.wait(2000)
    log.info(TAG, "=" .. string.rep("=", 40))
    log.info(TAG, "  开始初始化...")
    log.info(TAG, "=" .. string.rep("=", 40))

    -- 初始化摄像头 + 人脸模组 (含 GPIO12 供电)
    local result = exfacecam.open({
        id = camera.USB,
        sensor_width = CAM_W,
        sensor_height = CAM_H,
        usb_port = 1,
        face_uart = 2,
        face_rst = nil,
    })
    if not result then
        log.error(TAG, "exfacecam.open() 失败")
        return
    end
    log.info(TAG, "初始化完成")

    -- 查询模组版本
    local ver_ok, ver = exfacecam.get_version()
    if ver_ok then log.info(TAG, "模组固件: " .. ver) end

    -- 列出现有用户
    doListUsers()

    -- 清空已有用户，重新录入测试（demo专用，正式项目删除此段）
    log.info(TAG, "清空已有用户...")
    local del_ok = exfacecam.clear()
    log.info(TAG, "清空结果:", del_ok)

    doRegister("TestUser", 0)
    -- 录入完成后留出时间，供测试者调整姿态再进行验证
    sys.wait(2000)

    -- 确认入库
    log.info(TAG, "--- 入库后再次列出 ---")
    doListUsers()

    -- 测试验证
    doVerify()

    -- 清理
    exfacecam.close()
    log.info(TAG, "=" .. string.rep("=", 40))
    log.info(TAG, "  测试完成")
    log.info(TAG, "=" .. string.rep("=", 40))
end

sys.taskInit(mainTask)
