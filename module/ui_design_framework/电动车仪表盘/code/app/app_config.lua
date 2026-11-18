--[[
  app_config.lua  全局配置：硬件参数 / 双主题色板 / 布局常量 / 业务常量
  Air8607 10.1 寸 1024x600 RGB 屏 + GT911 触摸

  视觉基调「Aurora Cockpit」：
    近黑画布 + 发丝描边卡片 + 三色霓虹强调（青 / 紫 / 品红），
    所有颜色都成对给出（亮色 + 压暗色），避免依赖透明度（AirUI 容器透明度不带子控件）。
]]

local M = {}

-- ======================= 颜色工具 =======================
-- 线性混色：k = b 的权重（0..1）。只在构建调色板时调用，运行期不走这里
local function mix(a, b, k)
  k = k or 0.5
  local ar, ag, ab = math.floor(a / 65536) % 256, math.floor(a / 256) % 256, a % 256
  local br, bg, bb = math.floor(b / 65536) % 256, math.floor(b / 256) % 256, b % 256
  local r = math.floor(ar + (br - ar) * k + 0.5)
  local g = math.floor(ag + (bg - ag) * k + 0.5)
  local bl = math.floor(ab + (bb - ab) * k + 0.5)
  return r * 65536 + g * 256 + bl
end
-- ======================= 硬件参数 =======================
M.HW = {
  screen = {
    w = 1024, h = 600,
    panel_w = 1024, panel_h = 600,
    -- 时序对齐 Air8607 出厂固件 eng_8607_10i_v0.lua
    hbp = 140, hspw = 20, hfp = 160,
    vbp = 20,  vspw = 3,  vfp = 12,
    bus_speed = 50000000,            -- 50MHz
    pin_rst   = 15,                  -- LCD 复位
    pin_pwr   = 15,                  -- 背光使能（复用复位脚拉高）
    pwm_ch    = 3,                   -- 背光 PWM3 / GPIO13
    pwm_freq  = 1000,                -- 1kHz
  },
  tp = {
    ic       = "gt911",
    i2c_id   = 1,                    -- I2C1
    pin_rst  = 14,
    pin_int  = 51,
    int_type = "falling",
  },
}

-- ======================= 动画 / 刷新节奏 =======================
-- 分级刷新：数字 30fps、指针 15Hz、进度弧 5Hz、灯 10Hz、时钟 1Hz。
-- 表盘动态层是 412x412，每失效一次就要重画整块（下压着侧光/轨道/刻度数字/进度弧，
-- 上面盖着氛围光），降频是这块屏最有效的省帧手段。真车 CAN 也就 10~20Hz，15Hz 不肉。
--
-- 【阈值必须落在帧数之间，不能贴边】
-- 这些 ms 值是「累加 dt 到阈值」用的，而 dt 只会在 frame_ms 的整数倍附近出现
-- （33.3 / 66.6 / 99.9 …）。阈值贴边就会在 N 帧 / N+1 帧之间来回跳，
-- 同一层忽快忽慢。取值规则：(N-1)*33 < 阈值 < N*33，留 3ms 以上余量。
--   指针 2 帧 = 66.6ms → 60   弧 6 帧 = 199.8ms → 180   灯 3 帧 = 99.9ms → 90
M.ANIM = {
  frame_ms = 33,     -- 主循环节拍（约 30fps）
  sweep_s  = 1.6,    -- 开机扫针总时长（秒）
  need_ms  = 60,     -- 指针：2 帧 ≈ 66.6ms（原 50 = 20Hz，动态层整块重画太贵）
  prog_ms  = 180,    -- 进度弧：6 帧 ≈ 200ms（原写 200 贴死 6 帧边界 → 实际 7 帧 233ms，慢 15%）
  ind_ms   = 90,     -- 指示灯：3 帧 ≈ 100ms（原写 100 贴死 3 帧边界 → 实际 4 帧 133ms，慢 33%）
  dot_ms   = 750,    -- LIVE 呼吸半周期
}

-- ======================= 业务常量 =======================
M.MAX_SPEED = 160        -- 表盘满量程（对应 270° 扫描角）
M.START_ANG = 135        -- 表盘起始角（y 向下，0° 在 3 点钟方向）
M.SWEEP_ANG = 270        -- 扫描角度

-- ======================= 字号阶梯（hzfont 实例数 = 5） =======================
-- 中文最小 16；hzfont 真实行高 = 字号 + 3，ui_widget.label 会自动按此兜底
M.SIZES = {
  micro = 16,   -- 分区标题 / 单位 / 辅助说明
  label = 18,   -- 次级数值、单位
  value = 22,   -- 时钟 / 辅助数值
  big   = 34,   -- 卡片主数值
  hero  = 64,   -- 数字车速
}

-- ======================= 布局常量（设计画布 = 实机 1024x600） =======================
M.LAYOUT = {
  -- 页面
  px = 0, py = 0, pw = 1024, ph = 600,
  mx = 24,                    -- 左右安全边距

  -- 侧栏（左：指示灯 / 模式 / 时长；右：指示灯 / 电量）
  col_w   = 232,
  left_x  = 24,
  right_x = 768,              -- 768 + 232 = 1000 = 1024 - 24
  card_y1 = 64,  card_h1 = 152,
  card_y2 = 228, card_h2 = 152,   -- 228 = 64 + 152 + 12（左列模式卡）
  card_y3 = 392, card_h3 = 92,    -- 392 = 228 + 152 + 12；392 + 92 = 484
  -- 右列大电量卡：输出功率卡删除后，空出的 228..380 并入电量卡 → 228..484，
  -- 底边与左列三卡的 484 齐平。功率卡是侧栏里唯一「每 150ms 重建 shape」的卡，
  -- 删掉它省下的不只是 232x152 的重绘，还有每秒 6.7 次 items 表的 free/malloc。
  batt_y  = 228, batt_h = 256,

  -- 底部数据带
  band_y = 496, band_h = 88,      -- 496 + 88 = 584（上下各留 16 / 16）

  -- 表盘（中心 / 半径）
  dial_cx = 512, dial_cy = 290,
  ring_r  = 193, ring_w = 6,      -- 轨道外沿 196
  glow_r  = 204,                  -- 柔光外径（原 face_r=186 的实心面已删除：表盘改为透明）
  static_box = 408,               -- 静态层外框 = glow_r * 2
  dyn_box    = 412,               -- 动态层外框（指针 160 + 尾 26 + 线宽余量 < 206）
  tick_out      = 180,
  tick_in_major = 164,
  tick_in_mid   = 170,
  tick_in_minor = 174,
  num_r   = 148,                  -- 刻度数字半径
  needle_len = 160, needle_tail = 26, hub_r = 11,

  -- 表盘内文字（页面绝对坐标）
  brand_y = 176,                  -- 品牌：176..198
  hero_y  = 306, hero_h = 68,     -- 数字车速：306..374（在轴心下方，落在刻度开口区）
  unit_y  = 378,                  -- 单位：378..400
  odo_y   = 406,                  -- ODO：406..425
}

-- ======================= 背景层几何（色斑 + 底部氛围光） =======================
-- LVGL 9 没有径向渐变：设计稿的径向光靠「同心椭圆 + 递减 alpha」叠出来，
-- 全部画进一个全屏 shape 里，椭圆超出屏的部分由 shape 自身裁剪，不产生滚动条。
-- cx/cy 允许落在屏外（左右 -70 / 1094、底部 624 都是故意出血，保持弧形边缘）。
-- 为什么侧光不是「一个圆」：
-- 单层恒定 alpha 的椭圆 = 硬边圆斑（边界处 alpha 从 30 直接掉到 0），一眼就能看出是个圆。
-- 改成「圆心落到屏外 + 多层同心递减」后，屏幕里只看得到亮度渐变，看不到轮廓——
-- 这正是底部 amb 好看的原因（它圆心在 y=624，只露弧顶，且 6 层叠加）。
-- 半径必须「等距铺开」且跨过卡片宽度：若内层半径已经盖住整张卡，
-- 层数沿 x 不变 → 整张卡同一个 alpha，看起来就是「一片均匀的浅色」，没有梯度。
-- 3 层、每层 +100px（155→355）后，层数在卡片 x=24..256 内从 3 级掉到 1 级，
-- 梯度才会真正出现（见 orb 表右侧注释）。
M.GLASS = {
  -- 左右两束侧光（铺在卡片下面，给玻璃卡「可透」的内容）：
  -- 圆心 cx 固定在屏外 -70 / 1094，rx 以 100px 等距收窄（155→355），
  -- 最外层到 x=285 / x=739 为止，与表盘（306..718）之间空出 21px，光晕完全不进表盘。
  -- opa 从内到外 34→23（三层叠加 ≈ 30%），越靠屏幕外侧越浓、往屏内逐级变浅。
  -- 6 层 → 4 层 → 3 层：最后一次把最外层 rx=455 整层删掉，光晕的右边界从
  -- x=385 收到 x=285，**不再渗进表盘**（表盘左沿 306）。侧光外框随之从 385 缩到 285，
  -- 表盘 412x412 的每次重绘不再与侧光 bbox 相交，省掉约 7k px/帧 的 alpha 混合。
  -- 半径步进 100（155→355），单层 alpha 抬到 34/28/23，按 1-Π(1-ai/255) 反解，
  -- 三层全叠仍是 29.8%（原 30.1%）——峰值亮度不变，只是范围收窄。
  -- 半径参考：355 那圈在卡片 x=24 处 3 层全覆盖，卡片右端 x=256 已掉到 1 层。
  orb = {
    -- 左：dx = 到圆心 (-70) 的距离；cy 274 = 侧栏卡片 y64..484 的中线
    { cx = -70, cy = 274, rx = 155, ry = 149, opa = 34 },   -- dx ≤ 155（x ≤ 85） 3 层 = 29.8%
    { cx = -70, cy = 274, rx = 255, ry = 245, opa = 28 },   -- dx ≤ 255（x ≤ 185）2 层 = 19.0%
    { cx = -70, cy = 274, rx = 355, ry = 341, opa = 23 },   -- 最外圈 x ≤ 285，至此归零（1 层 9.0%）
    -- 右：与左束镜像（dx = 1094 - x）
    { cx = 1094, cy = 274, rx = 155, ry = 149, opa = 34 },
    { cx = 1094, cy = 274, rx = 255, ry = 245, opa = 28 },
    { cx = 1094, cy = 274, rx = 355, ry = 341, opa = 23 },
  },
  -- 档位光补偿（1 经济青 / 2 标准紫 / 3 运动品红）
  -- 系数 = 青的线性亮度 / 该色的线性亮度。sRGB 先线性化再按 0.2126R+0.7152G+0.0722B 加权：
  --   青 #22A8F5 L=0.349   紫 #A78BFA L=0.336   品红 #F472B6 L=0.347
  -- 青两次变蓝后亮度从 0.531 → 0.427 → 0.349，与紫/品红的差距从 55% 一路收到 3~4%，
  -- 所以补偿系数从 1.66/1.62 → 1.32/1.28 → 1.05/1.03（按六层 alpha 叠加 1-Pi(1-ai) 反解）。
  -- 外圈 opa 提不上去就到不了可见阈值，光会提前截止 → 真机「紫/品红小一圈」的根因。
  -- 落地后三档合成有效亮度：青 0.1059 / 紫 0.1066 / 品红 0.1070（差 <1%，肉眼同亮同大）。
  orbA = { 1.00, 1.05, 1.03 },
  -- 底部氛围光：设计稿两层径向渐变，各拆 3 阶同心椭圆逼近
  amb = {
    { cx = 512, cy = 624, rx = 486, ry = 150 },
    { cx = 512, cy = 624, rx = 324, ry = 100 },
    { cx = 512, cy = 624, rx = 162, ry = 50 },
    { cx = 512, cy = 600, rx = 297, ry = 66 },
    { cx = 512, cy = 600, rx = 198, ry = 44 },
    { cx = 512, cy = 600, rx = 99,  ry = 22 },
  },
}

-- ======================= 双主题调色板 =======================
local function finish(p)
  -- 由主色派生（不手写十六进制，改主色即自动协调）
  p.ringD1   = mix(p.ring1, p.bg, 0.62)   -- 轨道（暗态）
  p.ringD2   = mix(p.ring2, p.bg, 0.62)
  p.ringD3   = mix(p.ring3, p.bg, 0.62)
  p.ringEdge = mix(p.violet, p.bg, 0.74)  -- 柔光外发丝
  -- 表盘雾光不再进静态色板：它随档位变色，运行期由 M.mode_glow(i) 现算
  p.hubRim   = mix(p.hub, p.bg, 0.55)
  -- 幽灵水印（电量卡右侧那块电池轮廓）：AirUI 的 border_opa 固定 COVER，
  -- 描边色只能预混。基底不能取 bg——卡面是「玻璃白 + cardOpa」叠在 bg 上，
  -- 拿 bg 算出来只比卡面亮 2/255，暗色主题下等于没画。先还原卡面实际色，
  -- 再压 10% 文字色，深浅两套主题的明暗落差才是对称的。
  p.ghost    = mix(p.text, mix(p.cardGlass, p.bg, p.cardOpa / 255), 0.90)
  return p
end

-- 暗色 Neon Noir
local DARK = finish({
  dark = true,
  bg       = 0x07060E,
  -- 玻璃卡片（v3.1）：底色是「白 + cardOpa」，透出背后的色斑层（ui_backdrop）。
  -- AirUI 的 border_opa 固定 COVER、改不了透明度，所以描边/高光/发丝按 alpha 预混成实色。
  cardGlass = 0xFFFFFF,
  cardOpa   = 12,                 -- 4.8% 白
  cardEdge  = 0x3E3C47,           -- 15% 白叠在 bg 上的等效实色（设计稿实测 62,60,71）
  hairline  = 0xFFFFFF,
  hairOpa   = 15,                 -- 6% 白，卡内分隔线
  hlOpa     = 33,                 -- 13% 白，卡片顶部 1px 高光线
  text     = 0xEFEBFF,
  textDim  = 0x8F88AD,
  textMute = 0x5E5878,

  -- 经济档「青」：188°→196° 两轮之后真机仍被反馈偏绿，本轮推到 202°。
  -- 已走路径：0x22D3EE(188°, B/G 1.13) → 0x22BCF2(196°, 1.29) → 0x22A8F5(202°, 1.46)。
  -- 绿通道 188 → 168（-10.6%），蓝 245 几乎顶满，观感是「冰蓝」而不是「青绿」，
  -- 仍在青区（180~210°）不进入蓝紫；与紫 #A78BFA 色相差 53°，档位切换仍一眼能分。
  -- 代价：线性亮度 0.427 → 0.349（-18.2%），GLASS.orb 的 opa 同步 ×1.21 补回。
  cyan     = 0x22A8F5,
  violet   = 0xA78BFA,
  magenta  = 0xF472B6,
  amber    = 0xFBBF24,
  green    = 0x4ADE80,
  red      = 0xFB7185,

  ring1    = 0x22A8F5,
  ring2    = 0xA78BFA,
  ring3    = 0xF472B6,
  tickMajor= 0xEDD9F5,
  tickMid  = 0x7C6BA8,
  tickMinor= 0x3E3760,
  tickText = 0x9A92B8,

  brand    = 0x8B7BC0,
  unit     = 0x9C8AD6,
  needle   = 0xF472B6,
  needleTail = 0x5C1740,
  needleTip  = 0xFFF2FA,
  hub      = 0xF472B6,
  hubDot   = 0x2A0C22,

  btnBg    = 0xFFFFFF,
  btnBgOpa = 18,                  -- 半透明胶囊按钮底色
  btnEdge  = 0x1F1F26,            -- 10% 白预混
  btnIcon  = 0xEFEBFF,
  glowOpa  = 41,                  -- 表盘雾光 0.16
  orbK     = 1,                   -- 背景色斑不透明度系数
  ambOpa   = 9,                   -- 底部氛围光每个椭圆的 opa（6 层累积 ≈ 0.20）
})

-- 亮色 Neon Daylight
local LIGHT = finish({
  dark = false,
  bg       = 0xF4F5FA,
  cardGlass = 0xFFFFFF,
  cardOpa   = 173,                -- 68% 白（磨砂白）
  cardEdge  = 0xDCDEE6,           -- 10% #1E293B 叠在白底上的等效实色
  hairline  = 0xFFFFFF,
  hairOpa   = 20,                 -- 8%
  hlOpa     = 242,                -- 95% 白高光线
  text     = 0x161328,
  textDim  = 0x6C6885,
  textMute = 0x9793AB,

  cyan     = 0x088CD8,   -- 同暗色：色相 202°，与暗色 #22A8F5 对齐
  violet   = 0x7C3AED,
  magenta  = 0xD81B8C,
  amber    = 0xD97706,
  green    = 0x16A34A,
  red      = 0xDC2626,

  ring1    = 0x088CD8,
  ring2    = 0x7C3AED,
  ring3    = 0xD81B8C,
  tickMajor= 0x4C1D95,
  tickMid  = 0xB49BE8,
  tickMinor= 0xD8CDF0,
  tickText = 0x5A4A6A,

  brand    = 0x9C8CD0,
  unit     = 0x8B76C8,
  needle   = 0x7C3AED,
  needleTail = 0x3A1060,
  needleTip  = 0xD81B8C,
  hub      = 0xD81B8C,
  hubDot   = 0x3A1060,

  btnBg    = 0xFFFFFF,
  btnBgOpa = 184,                 -- 72% 白
  btnEdge  = 0xD8DCE8,
  btnIcon  = 0x161328,
  glowOpa  = 41,
  orbK     = 0.62,                -- 亮色下色斑整体压一档，否则浅底上发脏
  ambOpa   = 6,                   -- 6 层累积 ≈ 0.13
})

M.DARK = DARK
M.LIGHT = LIGHT

-- 当前主题色板：运行时被 set_theme 原地覆盖（引用不变，已缓存 C 的模块自动跟随）
M.C = {}
for k, v in pairs(DARK) do M.C[k] = v end

-- 原地覆盖键值，不替换表本身
function M.set_theme(name)
  local src = (name == "light") and LIGHT or DARK
  for k, v in pairs(src) do M.C[k] = v end
end

-- 表盘雾光色 = 档位色压暗 72% 后融进背景：暗色下是一层极淡的玻璃，亮色下也盖不住背景。
-- 对应设计稿的 --glow-fill（= mix(档位色, bg, .72)），随档位变色。
M.MODE_KEY = { "cyan", "violet", "magenta" }
function M.mode_glow(i)
  return mix(M.C[M.MODE_KEY[i or 2]] or M.C.violet, M.C.bg, 0.72)
end

-- 把颜色按比例压暗（指示灯「暗」态用，替代透明度 0.2）
function M.dim_hex(color, k)
  k = k or 0.22
  local r = math.floor(math.floor(color / 65536) % 256 * k + 0.5)
  local g = math.floor(math.floor(color / 256) % 256 * k + 0.5)
  local b = math.floor(color % 256 * k + 0.5)
  return r * 65536 + g * 256 + b
end

return M
