--[[
@module  face_demo
@summary Air1601/Air1602 + AirCAMERA_1034 USB摄像头 + AirCAMERA_1034摄像头人脸识别模组 人脸录入/验证应用模块
@version 2.2
@date    2026.08.20
@author  王城钧
@usage
本demo主要使用Air1601 + AirCAMERA_1034 USB摄像头 + AirCAMERA_1034摄像头人脸识别模组完成以下功能：
1、初始化USB主机模式，连接USB摄像头（AirCAMERA_1034）；
2、通过UART2（115200/8N1）与AirCAMERA_1034摄像头人脸识别模组通信；
3、查询模组固件版本、列出已注册用户、清空已有用户；
4、录入用户（register）；
5、验证用户（verify）。

接线：Air1601 UART2 TX/RX → 人脸模组 RX/TX（115200/8N1）；
前置：main.lua 中 require "face_demo"（注释掉其他业务模块）。

本文件没有对外接口，直接在main.lua中require "face_demo" 即可加载运行。
]]

local tag = "face_demo"
local exfacecam = require "exfacecam"

log.info(tag, "人脸识别demo启动")

-- 12号GPIO配置（AirCAMERA_1034摄像头供电控制引脚），需要拉高使能
gpio.setup(13, 1, gpio.PULLUP)

-- ======== 配置参数 ========
local cam_width = 1280       -- 摄像头采集宽度
local cam_height = 720       -- 摄像头采集高度
local verify_timeout = 15    -- 验证超时时间（秒）

-- ======== 实时人脸状态回调 (录入/验证过程中持续触发) ========
local function on_face_state(state, left, top, right, bottom, yaw, pitch, roll)
    local state_name = ({
        [0] = "正常", [1] = "无人脸", [2] = "偏上", [3] = "偏下",
        [4] = "偏左", [5] = "偏右", [6] = "太远", [7] = "太近",
        [8] = "眉毛遮挡", [9] = "眼睛遮挡", [10] = "面部遮挡",
        [11] = "角度异常"
    })[state] or ("未知:" .. state)
    if state ~= 1 then
        log.info(tag, string.format("人脸[%s] 框(%d,%d,%d,%d) 姿态yaw=%d pitch=%d roll=%d",
            state_name, left, top, right, bottom, yaw, pitch, roll))
    else
        log.info(tag, "请正对摄像头")
    end
end

-- ======== 录入用户 ========
local function do_register(name, is_admin)
    log.info(tag, "开始录入:", name, is_admin and "(管理员)" or "")
    local ok, user_id = exfacecam.register({
        name = name,
        admin = is_admin and 1 or 0,
        timeout = 15,
        on_state = on_face_state,
    })
    if ok then
        log.info(tag, string.format("录入成功! user_id=%d, name=%s", user_id or -1, name))
        return user_id
    else
        log.error(tag, "录入失败, 错误码:", user_id)
        return nil
    end
end

-- ======== 验证用户 ========
local function do_verify()
    log.info(tag, "开始验证, 请正对摄像头...")
    local ok, result = exfacecam.verify({
        timeout = verify_timeout,
        on_state = on_face_state,
    })
    if ok and result and result.user_id then
        log.info(tag, string.format("验证成功! user_id=%d name=%s admin=%d status=%d",
            result.user_id, result.name, result.admin, result.unlock_status))
        return result
    elseif ok then
        log.info(tag, "验证通过但无用户数据")
    else
        log.error(tag, "验证失败, 错误:", result or "unknown")
    end
    return nil
end

-- ======== 列出所有用户 ========
local function do_list_users()
    local ok, count, ids = exfacecam.list()
    if ok then
        log.info(tag, string.format("共%d个用户:", count))
        for i, id in ipairs(ids) do
            local ok2, info = exfacecam.query(id)
            if ok2 then
                log.info(tag, string.format("  [%d] id=%d name=%s admin=%d", i, id, info.name, info.admin))
            else
                log.info(tag, string.format("  [%d] id=%d", i, id))
            end
        end
        return ids
    else
        log.warn(tag, "获取用户列表失败")
        return {}
    end
end

-- ======== 主流程 ========
local function main_task()
    -- 必要延时：GPIO12上电给USB摄像头供电后，需要时间完成上电稳定和USB枚举，
    -- 若立即调用exfacecam.open()可能因摄像头未就绪而失败
    sys.wait(2000)
    log.info(tag, "=" .. string.rep("=", 40))
    log.info(tag, "  开始初始化...")
    log.info(tag, "=" .. string.rep("=", 40))

    -- 初始化摄像头 + 人脸模组 (含 GPIO12 供电)
    local result = exfacecam.open({
        id = camera.USB,
        sensor_width = cam_width,
        sensor_height = cam_height,
        usb_port = 1,
        face_uart = 1,
        face_rst = nil,
    })
    if not result then
        log.error(tag, "exfacecam.open() 失败")
        return
    end
    log.info(tag, "初始化完成")

    -- 查询模组版本
    local ver_ok, ver = exfacecam.get_version()
    if ver_ok then log.info(tag, "模组固件: " .. ver) end

    -- 列出现有用户
    do_list_users()

    -- 清空已有用户，重新录入测试（demo专用，正式项目删除此段）
    log.info(tag, "清空已有用户...")
    local del_ok = exfacecam.clear()
    log.info(tag, "清空结果:", del_ok)

    do_register("TestUser", 0)
    -- 必要延时：录入完成后留出时间，供测试者调整姿态，再开始验证
    sys.wait(2000)

    -- 确认入库
    log.info(tag, "--- 入库后再次列出 ---")
    do_list_users()

    -- 测试验证
    do_verify()

    -- 清理
    exfacecam.close()
    log.info(tag, "=" .. string.rep("=", 40))
    log.info(tag, "  测试完成")
    log.info(tag, "=" .. string.rep("=", 40))
end

sys.taskInit(main_task)
