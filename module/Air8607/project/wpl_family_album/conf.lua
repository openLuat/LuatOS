--[[
@module  conf
@summary Air8607 电子相册 - 板级与业务参数
@version 1.0
@date    2026.10.22
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡

所有硬件参数与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
  LCD_DISP = GPIO15   SD_EN = GPIO74   SPI1_CS = GPIO8
  GT911: I2C1(400k)  TP_RST = GPIO14  TP_INT = GPIO51
  背光: PWM3(GPIO13)

改板子只需要改这一个文件，其它模块不写死引脚。
]]

return {
    -- 屏幕逻辑分辨率
    W = 1024,
    H = 600,

    -- ===== TF / SD 卡（SPI1）=====
    sd = {
        spi_id   = 1,
        pin_cs   = 8,
        pin_en   = 74,            -- SD_EN，高电平使能供电
        speed    = 20 * 1000 * 1000,
        mount    = "/sd",
        scan_max = 600,           -- 单目录最多扫描多少个条目（防止超大目录吃内存）
        page_size = 100,          -- io.lsdir 单次分页条数（库上限 100）
    },

    -- ===== 中文字库 =====
    font = {
        size      = 16,
        cache_size = 2048,
        antialias = 1,
    },

    -- ===== 锁屏密码 =====
    lock = {
        enabled = true,           -- 开机是否要输密码
        pwd     = "1234",         -- 初始密码（4 位数字），首次开机后可在首页“改密码”里修改
        digits  = 4,              -- 位数
    },

    -- ===== 相册业务 =====
    photo = {
        exts      = { jpg = true, jpeg = true },   -- 视频解码通道只吃 JPEG，PNG 会走到图片通道且极易 OOM
        auto_sec  = 3,            -- 自动轮播间隔（秒）
        -- 全屏显示：先解一帧 RGB565 写成 .bin，再由 airui.image 按行读（运行期零大块）
        prefetch  = true,         -- 看当前这张时，后台把下一张也生成好
        -- 首选解码方式：sw / hw（失败会自动换另一种）
        -- Air8607 实测：hw 解码器还要额外申请硬解上下文，内存紧张时先失败；
        -- 相册是静态照片，sw 解 1024x600 约 0.3~0.8s，更稳，所以默认 sw。
        decode    = "sw",
        bar_hint_ms = 4000,       -- 控制条显示后自动隐藏时间
        touch_debug = true,       -- 打印触摸事件（排查卡顿用，稳定后可改 false）
        -- 打印“点击小图 / 上一张 / 下一张 / 轮播 -> 照片真正画完”的用时。
        -- 打开时会用 airui.full_refresh()（内部 lv_refr_now）同步重绘，才能把
        -- “取图”和“上屏”分开计时；稳定后可以改 false。
        time_debug = true,
        swipe_min_dx = 60,        -- 左右滑动最小位移（像素）
        swipe_max_ms = 1200,      -- 滑动最大持续时间
        tap_slop = 24,            -- 轻触判定容差
        tap_max_ms = 600,
        grid_cols = 2,            -- 每页 2x2 = 4 个大卡片
        grid_rows = 2,

        -- 目录页预览图
        -- true  = 用 thumb.lua 生成的 .bin 小图（204x120，约 49KB/张），内存占用很小
        -- false = 只显示图标 + 文件名（不读照片内容）
        preview = true,
        thumb_factor = 5,         -- 缩略图采样倍数：1024x600 → 204x120
        -- 缩略图缓存文件名前缀（相对 SD 挂载点，约 48KB/张）。
        -- 点开头，目录枚举会跳过，所以在相册里看不见；删掉这些文件即可全部重建。
        -- 前缀里带版本号（at3），换算法时改这里，启动时会自动清掉旧前缀的残留。
        thumb_prefix = "/.at3_",
    },
}
