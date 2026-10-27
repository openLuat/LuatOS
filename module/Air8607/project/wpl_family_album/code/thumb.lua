--[[
@module  thumb
@summary 目录页缩略图：直接让 airui.image 显示 JPEG 原图，LVGL 绘制时自动缩放到控件尺寸
@version 2.0
@date    2026.10.25

=== 为什么不再生成 .bin 小图 ===
旧版（v1.0）把 JPEG 解成 RGB565 → 面积平均缩成 204x120 → 写 /.athumb_*.bin（49KB），
理由是 LVGL 解 JPEG 按原图尺寸（SW 1.84MB/张），一页 4 张会 OOM。
现在条件已变：
  1. HW JPEG 硬解已激活（LUAT_USE_AIRUI_JPG_HW_ANY_SIZE），解码缓冲 1.23MB RGB565；
  2. airui 解码器 HW 失败后会自动 lv_image_cache_drop(NULL) 清缓存再重试；
  3. LVGL 的 fit="cover"/"contain" 是绘制时缩放，控件多小都不需要预缩图文件。
所以 build() 直接返回原图路径，不再解码、不再写 SD、不再占盘。
]]
local conf = require "conf"

local M = {}

--[[对外入口：返回原图路径，直接给 airui.image 显示
@param table entry {name, path, size}
@return string path
]]
function M.build(entry)
    return entry and entry.path or nil
end

return M
