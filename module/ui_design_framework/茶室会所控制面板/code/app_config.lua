--[[
App 级配置：屏幕、版面令牌、设备表、场景表、文案
所有数字都是 1024x600 绝对布局基准；页面里的坐标必须来自这里或本页顶部常量，
禁止在函数体里散落魔法数
]]

local M = {}

M.W, M.H = 1024, 600

-- 版面：左轴导航 / 顶栏 / 舞台 / 底部场景条（与 docs/index.html 同一套比例）
M.LAY = {
    rail_w = 88,
    head_h = 58,
    stage_x = 88,
    stage_y = 58,
    stage_w = 936,
    stage_h = 412,
    tray_y = 470,
    tray_h = 130,
}
M.rail_w = M.LAY.rail_w
M.head_h = M.LAY.head_h
M.stage_y = M.LAY.stage_y
M.tray_y = M.LAY.tray_y

-- 字号令牌。hzfont 行高 = 字号 + 3，控件高按 sz+3 下限保护（G3）
-- 中文最小 16（F2）：mini 就是下限，不要再往下取
M.FONT = {
    brand = 22,   -- 房间名
    hero = 27,    -- 大卡标题
    sub = 20,     -- 面板小标题
    body = 18,    -- 卡片名 / 按钮标题
    mini = 16,    -- 说明、英文副标、档位
    time = 25,    -- 顶栏时钟
}

M.MAX_LEVEL = 10
M.QUICK = { 2, 6, 9 }

-- 设备表：5 路，最常用的茶台灯光排在第 1 位
-- img / img_p     大卡与详情左图（夜 420×376 / 纸 418×374）
-- img_s / img_p_s 小卡（夜 216×180 / 纸 214×178）
--   **尺寸必须与控件 1:1**，不要让组件去缩：真机上缩放走逐像素采样，
--   而且图一旦比缓存池的余量大就会被淘汰，切主题时全部重新解码（实测 685ms）。
--   改卡片几何时同步改 tools/make_assets.py 里的四个尺寸常量，否则又会变成缩放。
-- img   暖夜素材（暗调照片，字压在上层要用浅色）
-- img_p 宣纸素材（晨光浅调，字压在上层要用深墨）
-- 随代码目录打包，运行时落在 /luadb/ 下
M.DEVICES = {
    { key = "light",   name = "茶台灯光", en = "TEA TABLE LIGHT",
      img = "/luadb/dev_light.jpg",   img_p = "/luadb/p_light.jpg",
      img_s = "/luadb/dev_light_s.jpg", img_p_s = "/luadb/p_light_s.jpg",
      desc = "主位吊灯与茶台灯带联动，越暗越显汤色" },
    { key = "incense", name = "香薰",     en = "INCENSE",
      img = "/luadb/dev_incense.jpg", img_p = "/luadb/p_incense.jpg",
      img_s = "/luadb/dev_incense_s.jpg", img_p_s = "/luadb/p_incense_s.jpg",
      desc = "炉火保温，香片渐展；浓度过高会压住茶香" },
    { key = "music",   name = "背景音乐", en = "TEA AMBIENCE",
      img = "/luadb/dev_music.jpg",   img_p = "/luadb/p_music.jpg",
      img_s = "/luadb/dev_music_s.jpg", img_p_s = "/luadb/p_music_s.jpg",
      desc = "古琴与流水按场景自动收放，不抢谈话" },
    { key = "humid",   name = "加湿",     en = "HUMIDITY",
      img = "/luadb/dev_humid.jpg",   img_p = "/luadb/p_humid.jpg",
      img_s = "/luadb/dev_humid_s.jpg", img_p_s = "/luadb/p_humid_s.jpg",
      desc = "雾量细密，维持 55% 上下最宜闻香" },
    { key = "ambient", name = "氛围",     en = "ATMOSPHERE",
      img = "/luadb/dev_ambient.jpg", img_p = "/luadb/p_ambient.jpg",
      img_s = "/luadb/dev_ambient_s.jpg", img_p_s = "/luadb/p_ambient_s.jpg",
      desc = "纱帘、屏风与烛影，决定进门的第一印象" },
}

--[[
小卡素材缺失时的兜底：
  1:1 小图只是性能优化，缺图绝不能变成白屏。资源没跟着脚本一起下载是全量重建
  最容易被截断的一环（真机日志里就是一串 airui_fs: failed to open ..._s.jpg），
  此时退回大图——会缩放、会慢一点，但界面是完整的。
  纯 io 存在性判断，启动时做一次，不进热路径。
]]
local function file_ok(path)
    if not path then return false end
    local ok, has = pcall(io.exists, path)
    return ok and has
end

for _, d in ipairs(M.DEVICES) do
    if not file_ok(d.img_s) then
        log.warn("cfg", "小卡素材缺失，回退大图", d.img_s)
        d.img_s = d.img
    end
    if not file_ok(d.img_p_s) then
        log.warn("cfg", "小卡素材缺失，回退大图", d.img_p_s)
        d.img_p_s = d.img_p
    end
end

-- 一键场景：levels 与 DEVICES 一一对应，0 表示该路关闭
M.SCENES = {
    { name = "待客", en = "RECEPTION",  num = "壹", levels = { 7, 3, 4, 4, 5 }, hint = "灯火明亮，香不压茶" },
    { name = "静修", en = "QUIET",      num = "贰", levels = { 2, 6, 1, 2, 1 }, hint = "一盏孤灯，只留余香" },
    { name = "茶会", en = "TEA GATHER", num = "叁", levels = { 8, 4, 5, 6, 4 }, hint = "众人围坐，声光皆宜" },
    { name = "清场", en = "CLEAR",      num = "肆", levels = { 0, 0, 0, 0, 0 }, hint = "熄灯落锁，静待来客" },
}

-- 顶栏
M.ROOM = { name = "松风阁", meta = "A3 包间 · 预约 20:00 · 4 位", badge = "待客中" }

--[[
假时钟基准：板上没有时间源（无联网对时，RTC 也没人写过），os.date 拿回来的
是 1970 那种出厂值。界面需要的是"看着正常、会走字"，不是"与世界时间一致"。

上电从这个钟面起走：20:00 正好是晚市开场，和顶栏那句"预约 20:00"对得上。
日期从 2026-11-19 起，跨零点自动进位（wday 用 Lua 口径：1=周日 … 5=周四）。
只保证自洽，不保证准确；哪天板上有了 RTC / NTP，这一段会自动让位给真时间。
]]
M.CLOCK = { hour = 20, min = 0, year = 2026, month = 11, day = 19, wday = 5 }

-- 文案
M.txt = {
    rail_scene = "场景",
    rail_service = "服务",
    rail_mute = "静音",
    rail_theme = "主题",
    tray_title = "一键场景",
    tray_note = "每晚 23:00 自动清场",
    seg_level = "档",
    panel_strength = "强度",
    panel_step = "灯光明暗",
    panel_quick = "快捷档位",
    panel_quote = "茶烟轻扬，一室生香",
    panel_back = "返回场景墙",
    theme_night = "暖夜",
    theme_paper = "宣纸",
    toast_scene = "已切换到「%s」",
    toast_saved = "设置已保存",
    toast_bell = "已呼叫前台",
    toast_mute = "已静音",
    toast_unmute = "已取消静音",
}

return M
