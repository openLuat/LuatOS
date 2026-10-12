-- PC 模拟器摄像头扫码测试（需要本机有摄像头，Windows / Media Foundation）
-- 用法: cd bsp/pc/build/out && ./luatos-lua.exe ../../../test/155.camera_scan/
PROJECT = "camera_scan_pc"
VERSION = "1.0.0"

local function main()
    if not camera then
        log.error("scan", "camera 库不存在")
        os.exit(1)
    end
    if type(camera.utest_qr_decode) == "function" then
        log.warn("scan", "当前为 utest 构建, camera.utest_qr_decode 可用")
    end

    local ok = camera.init({sensor_width = 640, sensor_height = 480})
    log.info("scan", "camera.init", ok)
    if not ok then
        log.error("scan", "摄像头初始化失败(无摄像头或设备被占用)")
        os.exit(1)
    end

    camera.on(0, "scanned", function(id, str)
        log.info("scan", "扫码成功, camera_id =", id, "内容 =", str)
        camera.stream(0, nil, nil, nil, nil, false)
        camera.close(0)
        os.exit(0)
    end)

    -- scan_enable = true，开启扫码（PC 侧后台定时抓帧 + ZXing 解码）
    local ret = camera.stream(0, nil, nil, nil, false, true)
    log.info("scan", "camera.stream(scan_enable=true)", ret)

    sys.taskInit(function()
        sys.wait(20000)
        log.error("scan", "20 秒内未扫到任何条码/二维码")
        camera.stream(0, nil, nil, nil, nil, false)
        camera.close(0)
        os.exit(1)
    end)
end

sys.taskInit(main)
sys.run()
