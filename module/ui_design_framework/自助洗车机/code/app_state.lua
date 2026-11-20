--[[
@module  app_state
@summary 洗车业务数据层（套餐 / 附加服务 / 计价 / 订单 / 工序）
@version 1.0.0
@note 与 docs/方案A_水光玻璃.html 的 PKGS / ADDONS / calc() 一一对应：
      计价 = 套餐价 + 附加服务价 −（小计 ≥50 时满减 8 元）。
      洗车过程按「演示加速 10×」推进（HTML 的 SPEED = 10）。
]]
local M = {}

M.SPEED = 10                       -- 演示加速：真实 1 秒 = 演示里 10 秒

M.plate = "沪A·8K7Q2"
M.car   = "已识别 · 小型车"
M.bay   = "洗车房 A"

-- 套餐（dur 为真实秒数，和 HTML 的 total 一致）
M.pkgs = {
    { id = 1, name = "极速冲洗", desc = "日常浮尘 · 快速完洗", dur = 270, price = 19, list = 29,
      steps = { { n = "高压预洗", t = 60 }, { n = "泡沫覆盖", t = 60 },
                { n = "清水冲洗", t = 60 }, { n = "强力风干", t = 90 } } },
    { id = 2, name = "精洗养护", desc = "泡沫精洗 + 水蜡镀膜", dur = 510, price = 39, list = 59, rec = "推荐",
      steps = { { n = "预洗润湿", t = 60 }, { n = "泡沫覆盖", t = 90 }, { n = "毛刷清洁", t = 120 },
                { n = "高压冲洗", t = 90 }, { n = "水蜡镀膜", t = 60 }, { n = "强力风干", t = 90 } } },
    { id = 3, name = "全效镀膜", desc = "七道工序 + 镀膜抛光", dur = 720, price = 69, list = 99,
      steps = { { n = "预洗润湿", t = 60 }, { n = "虫渍软化", t = 90 }, { n = "泡沫覆盖", t = 120 },
                { n = "毛刷精洗", t = 150 }, { n = "高压冲洗", t = 120 }, { n = "水蜡镀膜", t = 90 },
                { n = "镀膜抛光", t = 90 } } },
}

M.addons = {
    { id = "bug",   name = "虫渍", price = 8 },
    { id = "wheel", name = "轮毂", price = 10 },
    { id = "inner", name = "内饰", price = 12 },
}

-- 运行态（切主题重建页面时保留）
M.cur      = 2                     -- 当前套餐下标（默认精洗养护）
M.picked   = {}                    -- 附加服务勾选：{bug=true}
M.stage    = "select"              -- select / wash / done
M.rating   = 5
M.tags     = {}                    -- 评价标签
M.elapsed  = 0                     -- 已洗秒数（真实秒）
M.total    = 510
M.order    = nil                   -- 完成订单
M.rating_tags = { "洗得干净", "泡沫丰富", "速度快", "价格实惠" }

function M.pkg() return M.pkgs[M.cur] end

function M.addon_on(id) return M.picked[id] and true or false end

function M.toggle_addon(id)
    M.picked[id] = (not M.picked[id]) or nil
end

-- 计价：套餐 + 附加 − 满减
function M.calc()
    local p = M.pkg()
    local add = 0
    for _, a in ipairs(M.addons) do
        if M.picked[a.id] then add = add + a.price end
    end
    local sub = p.price + add
    local disc = (sub >= 50) and 8 or 0
    return { base = p.price, add = add, sub = sub, disc = disc, total = sub - disc }
end

-- mm:ss
function M.fmt_mmss(sec)
    if sec < 0 then sec = 0 end
    sec = math.floor(sec + 0.5)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- 4′30″ / 1′00″
function M.fmt_dur(t)
    if t < 60 then return t .. "″" end
    return string.format("%d′%02d″", math.floor(t / 60), t % 60)
end

-- 完成后的用量估算（与 HTML 的 finished 展示一致）
function M.usage()
    local n = #M.pkg().steps
    return {
        water = string.format("%.1f", 28 + n * 2.4),
        kwh   = string.format("%.2f", 0.28 + n * 0.02),
        water_l = 28 + n * 2.4,
    }
end

-- 生成订单号：CW-8241
function M.make_order()
    M.order = { no = string.format("CW-%04d", math.random(1000, 9999)) }
    return M.order
end

return M
