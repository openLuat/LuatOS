--[[
display 图片绘制能力验证（Air8601 / 1024x600 HX8282 RGB 屏）

两种用法都覆盖：
  先加载再画： display.loadImage(path)  -> display.drawImage(img, x, y)
  直接给路径： display.drawImageFile(path, x, y)

判活 token：
  display_image_ok   全部用例通过
  display_image_fail 有失败项，明细见前一条日志

用法：把本目录整个下载到设备（logo.jpg 会随脚本一起下发到 /luadb/），
      复位后看串口日志。
]]

local sys = require "sys"

local W, H = 1024, 600

local function tick_us(t0)
    local ok, us = pcall(function()
        local t1 = mcu.tick64()
        local _, d = mcu.dtick64(t1, t0, 0)
        return d
    end)
    if ok then
        return us
    end
    return nil
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local d = f:read("*a")
    f:close()
    return d
end

sys.taskInit(function()
    log.info("disp_img", "lua_vm_ready")

    -- 1) 初始化 RGB 屏（Air8601 7寸 HX8282，时序来自引擎配置）
    local ok, err = display.init("custom", {
        id = 0,
        interface = "rgb",
        w = W,
        h = H,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20,  vspw = 3,  vfp = 12,
        pclk_hz = 50 * 1000 * 1000,
    })
    log.info("disp_img", "display.init", ok, err)
    if not ok then
        log.error("disp_img", "display_image_fail", "init")
        return
    end

    -- 背光 PWM3 点亮，否则看不到画面
    pcall(function()
        pwm.open(3, 1000, 100)
    end)

    local results = {}

    -- 2) 文件路径加载
    local t0 = mcu.tick64()
    local img = display.loadImage("/luadb/logo.jpg")
    local load_us = tick_us(t0)
    results.load_file = (img ~= nil)
    log.info("disp_img", "loadImage", results.load_file, "us", load_us)
    if not img then
        log.error("disp_img", "display_image_fail", "loadImage")
        return
    end

    -- 3) 内存数据加载
    local data = read_file("/luadb/logo.jpg")
    results.read_file = (data ~= nil)
    local img2 = data and display.loadImageData(data, "jpg") or nil
    results.load_mem = (img2 ~= nil)
    log.info("disp_img", "loadImageData", results.load_mem, "bytes", data and #data or 0)
    data = nil

    -- 4) 非法输入必须被拒绝
    local bad, bad_err = display.loadImageData("not an image", "jpg")
    local missing = display.loadImage("/luadb/no_such_file.jpg")
    results.reject_bad = (bad == nil and missing == nil)
    log.info("disp_img", "reject", results.reject_bad, bad_err)

    -- 5) 绘制到 draw_buf（不自动 flush），再手动 flush 上屏
    display.fill(0, 0, W - 1, H - 1, 0x001F)
    t0 = mcu.tick64()
    local d1 = display.drawImage(img, 40, 40)
    local draw_us = tick_us(t0)
    local d2 = img2 and display.drawImage(img2, 500, 320) or false
    display.flush()
    results.draw = (d1 == true and d2 == true)
    log.info("disp_img", "drawImage", d1, d2, "us", draw_us)

    -- 6) 越界拒绝、负坐标裁剪
    local off = display.drawImage(img, W + 10, H + 10)
    local clip = display.drawImage(img, -100, -100)
    results.clip = (off == false and clip == true)
    log.info("disp_img", "clip", off, clip)
    display.flush()

    -- 6.1) 一次性绘制：直接给路径，内部解码后立即绘制
    t0 = mcu.tick64()
    local once = display.drawImageFile("/luadb/logo.jpg", 40, 340)
    local once_us = tick_us(t0)
    local once_missing = display.drawImageFile("/luadb/no_such_file.jpg", 0, 0)
    results.draw_file = (once == true and once_missing == false)
    log.info("disp_img", "drawImageFile", once, once_missing, "us", once_us)
    display.flush()

    -- 7) 释放后不可再绘制
    local freed = display.freeImage(img)
    local after_free = display.drawImage(img, 0, 0)
    if img2 then
        display.freeImage(img2)
    end
    results.free = (freed == true and after_free == false)
    log.info("disp_img", "freeImage", freed, after_free)

    -- 汇总
    local all_ok = true
    for k, v in pairs(results) do
        if not v then
            all_ok = false
            log.error("disp_img", "case_failed", k)
        end
    end

    if all_ok then
        log.info("disp_img", "display_image_ok")
    else
        log.error("disp_img", "display_image_fail", "see case_failed above")
    end

    while true do
        sys.wait(1000)
    end
end)

sys.run()
