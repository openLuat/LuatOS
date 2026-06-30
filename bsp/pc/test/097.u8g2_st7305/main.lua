-- 模块功能:u8g2 ST7305 (168x384 单色 OLED) PC 模拟器 demo
-- 触发条件:spi_id == 21(对应 bsp/pc/ui/luat_u8g2_sdl2.c 中的 LUAT_PC_U8G2_EMU_ID)
-- 编译方式:build_windows_32bit_msvc_gui.bat
-- 备注:st7305 物理接口是 3-wire/4-wire SPI(没有 I2C),所以这里走 spi_hw_4pin;
--      bsp/pc/port/driver/luat_spi_pc.c 的 luat_spi_setup 已对 21 放行,
--      bsp/pc/ui/luat_u8g2_sdl2.c 会把 i2c_id/spi_id==21 的 display_cb 替换成 SDL2 渲染版本
-- 分辨率选择说明:
--   选 168x384 而不是 200x200,是因为 168x384 的 tile 完全对齐(21*8=168, 48*8=384),
--   m_21_48_f 的 8064 字节 buffer 就是标准 1bpp 位图,PC 模拟器 hijack 渲染完美;
--   200x200 的 tile_width=26 vs pixel_width=200 差 8 像素,buffer 不是标准 1bpp 布局,
--   在 PC 模拟器下会错位(真实硬件的 st7305 12-bit block 转换不可用,需要单独处理)
--   如需在真实硬件上使用 200x200,把 ic 改成 "st7305_200x200" 即可
-- direction 说明:
--   direction=0: 竖屏 168x384(物理原生方向),demo 自适应放大铺满全屏
--   direction=90: 横屏 384x168(把屏逆时针旋转 90°),demo 坐标需重新设计
--   推荐 direction=0,demo 已自适应大屏
-- 运行环境:
--   PC 模拟器下 168x384 物理像素小,在 24 寸显示器上只有 5cm 宽,字看着小而糊,
--   可用环境变量让 SDL2 窗口物理放大,1bpp 用最近邻放大保持黑白硬边:
--     set LUAT_U8G2_SDL2_SCALE=4   :: 168x384 -> 672x1536,字大 4 倍
--     set LUAT_U8G2_SDL2_SCALE=2   :: 168x384 -> 336x768
--   不设时默认 scale=1,跟 096 体验一致(对 128x64 屏刚好,大屏看着字小)
--   调试 dump(可选,把 SDL2 帧写到 bmp):
--     set LUAT_U8G2_SDL2_DUMP_BMP=COUNT:8   :: dump 8 整帧到 bsp/pc/u8g2_frame_*.bmp
-- @module u8g2_st7305
-- @author wendal
-- @release 2026.06.30

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "u8g2_st7305"
VERSION = "1.0.3"

log.info("main", PROJECT, VERSION)

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗


-- 主流程
sys.taskInit(function()

-- SPI 屏幕引脚配置(仅占位,模拟器不会真的去拉 GPIO;真实硬件接法参考模块原理图)
local spi_id, spi_res, spi_dc, spi_cs = 21, 0, 1, 2

-- 初始化 SPI 显示屏(走 PC 模拟器,弹出 SDL2 窗口)
log.info("init st7305_168x384 (PC emulator, spi_id=21, 168x384 1bpp full buffer, 竖屏 direction=0)")
u8g2.begin({ic = "st7305_168x384", direction = 0, mode = "spi_hw_4pin", spi_id = spi_id, spi_res = spi_res, spi_dc = spi_dc, spi_cs = spi_cs})

-- 屏尺寸,后面 demo 根据此尺寸自适应(避免只在顶部 0..64 区域画图导致大屏空荡)
local W, H = u8g2.GetDisplayWidth(), u8g2.GetDisplayHeight()  -- 168, 384
log.info("u8g2 st7305", "display size", W, "x", H)

-- 显示部分
u8g2.SetFontMode(1)
u8g2.ClearBuffer()
u8g2.SetFont(u8g2.font_opposansm12_chinese)
u8g2.DrawUTF8("U8g2+LuatOS", 32, 22)

if u8g2.font_opposansm12_chinese then
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
elseif u8g2.font_opposansm10_chinese then
    u8g2.SetFont(u8g2.font_opposansm10_chinese)
elseif u8g2.font_sarasa_m12_chinese then
    u8g2.SetFont(u8g2.font_sarasa_m12_chinese)
elseif u8g2.font_sarasa_m10_chinese then
    u8g2.SetFont(u8g2.font_sarasa_m10_chinese)
else
    print("no chinese font")
end

while true do

    -- 步骤 1: 显示宽高(直接用大屏尺寸,顶头)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("屏幕宽度", 0, 24)
    u8g2.DrawUTF8("屏幕高度", 0, 48)
    u8g2.DrawUTF8(":"..W, 80, 24)
    u8g2.DrawUTF8(":"..H, 80, 48)
    u8g2.SendBuffer()
    log.info("u8g2 st7305", "frame sent")

    -- 步骤 2: 画线测试(横线铺满整个屏宽,y 间距 60 像素,大屏纵向也铺开)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画线测试", 0, 24)
    for i = 0, W, 8 do
        u8g2.DrawLine(0, 60,  i, 60)
        u8g2.DrawLine(0, 120, i, 120)
        u8g2.DrawLine(0, 180, i, 180)
        u8g2.DrawLine(0, 240, i, 240)
        u8g2.SendBuffer()
        sys.wait(30)
    end

    -- 步骤 3: 画圆测试(铺满大屏,4 个不同位置)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画圆测试", 0, 24)
    u8g2.DrawCircle(W//4,   H//4,   30, 1)
    u8g2.DrawDisc  (W*3//4, H//4,   30, 1)
    u8g2.DrawCircle(W//4,   H*3//4, 30, 1)
    u8g2.DrawDisc  (W*3//4, H*3//4, 30, 1)
    u8g2.SendBuffer()

    -- 步骤 4: 椭圆测试(铺满大屏)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("椭圆测试", 0, 24)
    u8g2.DrawEllipse       (W//4,   H//4,   40, 20, 1)
    u8g2.DrawFilledEllipse (W*3//4, H//4,   40, 20, 1)
    u8g2.DrawEllipse       (W//4,   H*3//4, 40, 20, 1)
    u8g2.DrawFilledEllipse (W*3//4, H*3//4, 40, 20, 1)
    u8g2.SendBuffer()

    -- 步骤 5: 方框测试(铺满大屏)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("方框测试", 0, 24)
    u8g2.DrawBox  (W//4 - 20,  H//4 - 20,   40, 40)
    u8g2.DrawFrame(W*3//4-20, H//4 - 20,   40, 40)
    u8g2.DrawBox  (W//4 - 20,  H*3//4-20,  40, 40)
    u8g2.DrawFrame(W*3//4-20, H*3//4-20,  40, 40)
    u8g2.SendBuffer()

    -- 步骤 6: 圆角方框测试
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("圆角方框", 0, 24)
    u8g2.DrawRBox  (W//4 - 20,  H//4 - 20,   40, 40, 8)
    u8g2.DrawRFrame(W*3//4-20, H//4 - 20,   40, 40, 8)
    u8g2.DrawRBox  (W//4 - 20,  H*3//4-20,  40, 40, 8)
    u8g2.DrawRFrame(W*3//4-20, H*3//4-20,  40, 40, 8)
    u8g2.SendBuffer()

    -- 步骤 7: 三角测试(铺满大屏,大三角)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("三角测试", 0, 24)
    u8g2.DrawTriangle(W//4, H*3//4, W//2, H//4, W*3//4, H*3//4)
    u8g2.SendBuffer()

    -- 步骤 8: 二维码(放大到 80 像素,放在屏中央)
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("QR 码", 0, 24)
    local qr_size = 80
    u8g2.DrawDrcode((W - qr_size) // 2, (H - qr_size) // 2 + 20, "https://docs.openluat.com", qr_size)
    u8g2.SendBuffer()

    log.info("main", "u8g2 st7305 demo done")
end
end)

-- 主循环, 必须加
sys.run()
