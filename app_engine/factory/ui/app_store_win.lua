--[[
@module app_store_win
@summary 应用市场窗口
@version 1.0.4
@date 2026.04.14
@author 江访
@usage
本文件为应用市场窗口的UI实现，遵循无状态设计原则，核心功能为：
1. 提供应用市场的用户界面，包括分类选择、排序、搜索、分页显示
2. 通过exapp模块获取应用列表和已安装应用信息
3. 处理用户操作（安装、卸载、更新应用）并发布相应消息
4. 订阅exapp模块的消息更新UI状态

本文件不维护任何应用数据状态，所有数据实时从exapp模块查询。
所有用户操作通过发布以下消息触发：
1. APP_STORE_GET_LIST  - 请求获取应用列表（携带category, sort, page, size, query）
2. APP_STORE_INSTALL   - 安装应用
3. APP_STORE_UNINSTALL - 卸载应用
4. APP_STORE_UPDATE    - 更新应用

订阅的消息包括：
1. APP_STORE_LIST_UPDATED      - 应用列表更新
2. APP_STORE_INSTALLED_UPDATED - 已安装应用更新
3. APP_STORE_PROGRESS          - 下载安装进度
4. APP_STORE_ACTION_DONE       - 应用操作完成
5. APP_STORE_ERROR             - 错误信息
6. APP_STORE_ICON_READY        - 图标下载完成

设计原则：
1. 无状态设计
2. 纯查询模式
3. 消息驱动
4. 及时刷新
]]
-- Abbreviations: ac=action sc=success an=app_name pg=page_info sm=sort_map cy=cat_y
--   bo=btn_obj act=active et=entry lp=local_path tst=toast lb=label vl=value
--   hn=hm_now tn=tp_now tl=total_now ca=cached pc=percent st=status_text ni=new_installed

local wid = nil
local mc = nil
local si = nil
local sk = nil
local ss = nil
local cb = {}
local cc = "全部"
local cs = "recommend"
local ac = nil
local ag = nil
local pl = nil
local pvb = nil
local nxb = nil

-- 布局参数
local th, sh, sw, aah, pbh, gah = 0, 0, 0, 0, 0, 0
local sbw, sbh = 0, 0
local sbrw = 0
local acw, ach = 0, 0
local agw, agh = 0, 0
local pbw = 0

local gm = 8
local cw, ch = 0, 0
local gc = 1
local isz = 0
local tfs = 0
local dfs = 0
local bfs = 0
local ifs = 0
local mdl = 2 -- 描述最大行数，动态计算

-- 按钮自适应参数
local cbh = math.floor(32 * _G.density_scale)
local cbbm = 8
local cp = 1
local tp = 0
local plim = 10
local hm = false
local cq = ""

-- 只保存UI状态，不保存业务数据
local lii = {}

-- 使用颜色
local COLOR_PRIMARY = 0x007AFF
local COLOR_PRIMARY_DARK = 0x0056B3
local COLOR_ACCENT = 0xFF9800
local COLOR_BG = 0xF5F5F5
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER = 0xE0E0E0
local COLOR_WHITE = 0xFFFFFF
local COLOR_DANGER = 0xE63946

local cats = { "全部", "已安装", "通信", "工具", "游戏", "工业", "健康" }
local piu = {}

-- 进度对话框相关
local pd = nil
local pbar = nil
local pbl = nil

-------------------------------------------------------------------------------
-- 布局计算
------------------------------------------------------------------------------
local function cl()
    -- 框架布局：从模板线性缩放
    -- 竖屏模板 480x854: top=68, sort=51, side=96, pbh=55
    -- 横屏模板 854x480: top=38, sort=28, side=136, pbh=40
    if is_landscape then
        local sy = screen_h / 480
        th = math.floor(38 * sy)
        sh = math.floor(28 * sy)
        sw = math.floor(136 * screen_w / 854)
        pbh = math.floor(40 * sy)
    else
        local sy = screen_h / 854
        th = math.floor(68 * sy)
        sh = math.floor(51 * sy)
        sw = math.floor(96 * screen_w / 480)
        pbh = math.floor(55 * sy)
    end
    sw = math.max(64, math.min(260, sw))
    sh = math.max(26, sh)
    pbh = math.max(28, math.min(60, pbh))

    -- 字体大小（全部 ≥ 14）
    local bf = math.floor(screen_h / 40 * _G.density_scale)
    bf = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(24 * _G.density_scale), bf))
    tfs = math.max(math.floor(16 * _G.density_scale), math.min(math.floor(26 * _G.density_scale), bf))
    dfs = math.max(math.floor(14 * _G.density_scale),
        math.min(math.floor(22 * _G.density_scale), bf - math.floor(2 * _G.density_scale)))
    bfs = math.max(math.floor(14 * _G.density_scale),
        math.min(math.floor(20 * _G.density_scale), bf - math.floor(2 * _G.density_scale)))
    ifs = bfs

    -- 图标大小
    if is_landscape then
        isz = math.max(math.floor(40 * _G.density_scale),
            math.min(math.floor(70 * _G.density_scale), math.floor(screen_h / 16 * _G.density_scale)))
    else
        isz = math.max(math.floor(40 * _G.density_scale),
            math.min(math.floor(70 * _G.density_scale), math.floor(screen_h / 14 * _G.density_scale)))
    end
    if screen_h < 360 then
        isz = math.max(math.floor(32 * _G.density_scale),
            math.min(math.floor(50 * _G.density_scale), math.floor(screen_h / 12 * _G.density_scale)))
    end

    -- 区域尺寸
    aah = screen_h - th - sh
    gah = aah - pbh - gm * 2

    sbw = screen_w - 2 * gm - 70 - 50
    sbh = math.max(32, math.min(math.floor(th * 0.72), th - 10))
    sbrw = screen_w
    acw = screen_w - sw
    ach = aah
    agw = acw - 2 * gm
    agh = gah
    pbw = acw

    -- 网格列数（动态计算，最小卡片宽度乘以 density_scale 适配高密度屏）
    local mcw
    if is_landscape then
        mcw = math.max(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.18 * _G.density_scale))
    else
        mcw = math.max(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.30 * _G.density_scale))
    end
    mcw = math.max(math.floor(150 * _G.density_scale), math.min(math.floor(280 * _G.density_scale), mcw))

    gc = math.max(1, math.floor(agw / mcw))

    if screen_w < 480 then
        gc = math.min(2, gc)
    elseif screen_w < 720 then
        gc = math.min(3, gc)
    elseif screen_w < 1800 then
        gc = math.min(4, gc)
    else
        gc = math.min(5, gc)
    end

    if screen_w <= 480 and not is_landscape then
        gc = 1
    end

    cw = math.floor((agw - (gc + 1) * gm) / gc)

    -- 卡片按钮高度
    if screen_h < 360 then
        cbh = math.max(math.floor(28 * _G.density_scale),
            math.min(math.floor(40 * _G.density_scale), math.floor(screen_h / 14 * _G.density_scale)))
    else
        cbh = math.max(math.floor(36 * _G.density_scale),
            math.min(math.floor(50 * _G.density_scale), math.floor(screen_h / 18 * _G.density_scale)))
    end

    -- 卡片高度与描述行数
    local tlh = tfs + 4
    local ilh = ifs + 4
    local dlh = dfs + 4
    local dl = 2

    local vpe = (screen_h < 400) and 8 or 12
    local bch = math.max(isz, tlh + ilh) + cbh + cbbm +
        vpe
    local ahd = gah - bch - gm * 2

    if ahd >= dlh * 2 then
        dl = 2
    elseif ahd >= dlh then
        dl = 1
    else
        dl = 0
    end

    local dh = dfs * dl + (dl > 0 and 8 or 0)
    ch = math.floor(bch + dh)

    -- 确保卡片高度足够容纳内部布局：描述 + 间距 + 按钮
    local ioy = 15 + tfs + 6
    local dsy = ioy + ifs + 8
    local rh = dsy + dh + 4 + cbh + cbbm
    ch = math.max(ch, math.floor(rh))

    local rpp = math.max(1, math.floor(gah / (ch + gm)))
    plim = gc * rpp

    mdl = dl

end

local function upd()
    if not pl then return end
    local text = tostring(cp)
    if tp > 0 then
        text = text .. "/" .. tp
    else
        text = text .. "/?"
    end
    pl:set_text(text)
end

-------------------------------------------------------------------------------
-- 进度对话框
-------------------------------------------------------------------------------
local function cpd()
    if pd then
        pd:destroy()
        pd = nil
        pbar = nil
        pbl = nil
    end
end

local function spd(an)
    cpd()
    local msk = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0x000000,
        color_opacity = 180,
    })
    local dlw = math.min(400, screen_w - 80)
    local dlh = 160
    local dlx = (screen_w - dlw) / 2
    local dly = (screen_h - dlh) / 2
    local dlg = airui.container({
        parent = msk,
        x = dlx,
        y = dly,
        w = dlw,
        h = dlh,
        color = COLOR_CARD,
        radius = 16,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    airui.label({
        parent = dlg,
        x = 20,
        y = 20,
        w = dlw - 40,
        h = 30,
        text = "正在安装 " .. (an or ""),
        font_size = tfs,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    local bar = airui.bar({
        parent = dlg,
        x = 20,
        y = 70,
        w = dlw - 40,
        h = 20,
        min = 0,
        max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 10
    })
    local tl = airui.label({
        parent = dlg,
        x = 20,
        y = 105,
        w = dlw - 40,
        h = 24,
        text = "准备下载...",
        font_size = dfs,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    pd = msk
    pbar = bar
    pbl = tl
end

local function sst(ac, an)
    local msg = ""
    if ac == "install" then
        msg = (an or "应用") .. " 安装完成"
    elseif ac == "uninstall" then
        msg = (an or "应用") .. " 卸载完成"
    elseif ac == "update" then
        msg = (an or "应用") .. " 更新完成"
    else
        msg = "操作完成"
    end
    local tst = airui.msgbox({
        title = "提示",
        text = msg,
        buttons = { "确定" },
        timeout = 1000,
        on_action = function(self, lb)
            if lb == "确定" then
                self:hide()
            end
            self:destroy()
        end
    })
    tst:show()
end

-------------------------------------------------------------------------------
-- 图标更新
-------------------------------------------------------------------------------
local function oir(aid, lp)
    local et = piu[aid]
    if et and et.image_component then
        et.image_component:set_src(lp)
    end
    piu[aid] = nil
end

-------------------------------------------------------------------------------
-- UI 创建（顶部栏、排序栏、分类侧边栏、内容区、分页栏）
-------------------------------------------------------------------------------
local function cui()
    mc = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h, color = COLOR_BG, parent = airui.screen
    })

    -- 顶部栏
    local tb = airui.container({
        parent = mc, x = 0, y = 0, w = screen_w, h = th, color = COLOR_CARD
    })
    local tih = math.min(38, math.floor(th * 0.82))
    local tiy = math.floor((th - tih) / 2)
    local tir = math.floor(tih / 2)
    airui.button({
        parent = tb,
        x = 8,
        y = tiy,
        w = tih,
        h = tih,
        text = "←",
        font_size = math.min(math.floor(24 * _G.density_scale), math.floor((tih - 4) * _G.density_scale)),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = tir, border_width = 1, border_color = COLOR_DIVIDER, pad = 0 },
        on_click = function()
            if wid then
                exapp.init()
                exwin.return_idle()
            end
        end
    })

    local sbwe = screen_w - tih - 12 - 60 - 8
    local sbhe = math.min(tih, sbh)
    local sbg = airui.container({
        parent = tb,
        x = tih + 12,
        y = tiy,
        w = sbwe,
        h = sbhe,
        color = COLOR_DIVIDER,
        radius = tir,
        border_width = 1,
        border_color = COLOR_DIVIDER
    })
    sk = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = screen_w,
        h = 200,
        bg_color = COLOR_CARD,
        on_commit = function(self)         -- 确认事件回调，只有在按下确认键时才会触发
            -- 隐藏键盘
            self:hide()
        end,
    })
    si = airui.textarea({
        parent = sbg,
        x = 8,
        y = 2,
        w = sbwe - 16,
        h = sbhe - 4,
        placeholder = "搜索应用...",
        font_size = bfs,
        color = COLOR_TEXT,
        keyboard = sk
    })
    local sbnw = math.min(60, screen_w - tih - 12 - sbwe - 8)
    airui.button({
        parent = tb,
        x = tih + 12 + sbwe + 4,
        y = tiy,
        w = sbnw,
        h = tih,
        text = "搜索",
        font_size = bfs,
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = tir, border_width = 0, pad = 4 },
        on_click = function()
            local q = (si and si:get_text()) or ""
            cq = q or ""
            cp = 1
            sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
        end
    })

    -- 排序栏
    local srb = airui.container({
        parent = mc,
        x = 0,
        y = th,
        w = sbrw,
        h = sh,
        color =
            COLOR_CARD
    })
    local stbh = math.min(36, math.floor(sh * 0.85))
    local stbr = math.floor(stbh / 2)
    local sddx = math.floor(12 * _G.density_scale)
    local sddw = math.min(150, math.floor((screen_w - sddx - 90) * 0.65))
    local srfx = sddx + sddw + 20
    if srfx + 70 > screen_w then
        sddw = math.floor(screen_w - sddx - 90)
        srfx = sddx + sddw + 10
    end
    ss = airui.dropdown({
        parent = srb,
        x = sddx,
        y = sort_by,
        w = sddw,
        h = stbh,
        options = { "推荐", "序号", "上传时间(旧)", "上传时间(新)", "热度", "下载量", "更新优先" },
        default_index = 0,
        style = { bg_color = COLOR_CARD, border_color = COLOR_DIVIDER, radius = stbr },
        on_change = function(self, idx, vl)
            local sm = { "recommend", "idAsc", "timeAsc", "timeDesc", "hot", "downloads", "updatePriority" }
            cs = sm[idx + 1] or "recommend"
            cp = 1
            sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
        end
    })
    airui.button({
        parent = srb,
        x = math.max(srfx, screen_w - 78),
        y = sort_by,
        w = math.min(70, screen_w - math.max(srfx, screen_w - 78) - 4),
        h = stbh,
        text = "刷新",
        font_size = bfs,
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = stbr, border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function()
            cp = 1
            sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
        end
    })

    -- 分类侧边栏
    local csb = airui.container({
        parent = mc,
        x = 0,
        y = th + sh,
        w = sw,
        h =
            aah,
        color = COLOR_CARD
    })
    local cy = 16
    local cth = math.max(36, math.min(50, math.floor(screen_h / 20)))
    local ctr = math.min(24, math.floor(cth / 2))
    local ctw = sw - 20
    for i, cat in ipairs(cats) do
        local btn = airui.button({
            parent = csb,
            x = 10,
            y = cy,
            w = ctw,
            h = cth,
            text = cat,
            font_size = bfs,
            style = {
                bg_color = (cat == cc) and COLOR_PRIMARY or COLOR_CARD,
                pressed_bg_color = COLOR_PRIMARY_DARK,
                text_color = (cat == cc) and COLOR_WHITE or COLOR_TEXT,
                radius = ctr,
                border_width = 1,
                border_color = COLOR_DIVIDER,
                pad = 0
            },
            on_click = function()
                if cc == cat then return end
                cc = cat
                for idx, bo in ipairs(cb) do
                    local act = (cats[idx] == cat)
                    bo:set_style({
                        bg_color = act and COLOR_PRIMARY or COLOR_CARD,
                        text_color = act and
                            COLOR_WHITE or COLOR_TEXT
                    })
                end
                cp = 1
                sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
            end
        })
        cb[i] = btn
        cy = cy + cth + 8
    end

    -- 右侧内容区
    ac = airui.container({
        parent = mc,
        x = sw,
        y = th + sh,
        w = acw,
        h =
            ach - pbh,
        color = COLOR_BG,
        scrollable = true,
    })
    ag = airui.container({
        parent = ac,
        x = gm,
        y = gm,
        w = agw,
        h =
            agh,
        color = COLOR_BG
    })

    -- 分页栏
    local pbhe = pbh
    local pgb = airui.container({
        parent = mc,
        x = sw,
        y = screen_h - pbh,
        w = screen_w -
            sw,
        h = pbh,
        color = COLOR_CARD
    })
    local pvx = 16
    local pvw = 70
    local nxw = 70
    local nxx = pbw - 86
    local lx = pvx + pvw + 4

    local pnbh = math.min(40, math.floor(pbh * 0.8))
    local pnby = math.floor((pbh - pnbh) / 2)
    local pnr = math.floor(pnbh / 2)

    pvb = airui.button({
        parent = pgb,
        x = pvx,
        y = pnby,
        w = pvw,
        h = pnbh,
        text = "上一页",
        font_size = math.max(math.floor(14 * _G.density_scale), bfs - math.floor(4 * _G.density_scale)),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = pnr, border_width = 0 },
        on_click = function()
            if cp > 1 then
                cp = cp - 1
                sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
                upd()
            end
        end
    })
    nxb = airui.button({
        parent = pgb,
        x = nxx,
        y = pnby,
        w = nxw,
        h = pnbh,
        text = "下一页",
        font_size = math.max(math.floor(14 * _G.density_scale), bfs - math.floor(4 * _G.density_scale)),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = pnr, border_width = 0 },
        on_click = function()
            if hm then
                cp = cp + 1
                sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
                upd()
            end
        end
    })
    pl = airui.label({
        parent = pgb,
        x = lx,
        y = math.floor((pbh - 30) / 2),
        w = screen_w - sw - nxw * 2 - 40,
        h = 30,
        text = "1/?",
        font_size = bfs,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-------------------------------------------------------------------------------
-- 渲染应用卡片（新布局：名称 → 信息行 → 描述 → 按钮）
-------------------------------------------------------------------------------
local function ra(apps, more)
    hm = more
    upd()

    if ag then ag:destroy() end

    local rn = math.ceil(#apps / gc)
    local ngh = math.max(gah, rn * (ch + gm) + gm + 10)
    ag = airui.container({
        parent = ac,
        x = gm,
        y = gm,
        w = agw,
        h = ngh,
        color = COLOR_BG
    })

    local ia = exapp.list_installed()
    local bh = cbh
    local bbm = cbbm
    local by = ch - bh - bbm

    for idx, app in ipairs(apps) do
        local lid = lii[tostring(app.aid)]
        if lid then app.installed = true end

        local col = (idx - 1) % gc
        local row = math.floor((idx - 1) / gc)
        local x = col * (cw + gm) + gm
        local y = row * (ch + gm) + gm

        local card = airui.container({
            parent = ag,
            x = x,
            y = y,
            w = cw,
            h = ch,
            color = COLOR_CARD,
            radius = 16,
            border_width = 1,
            border_color = COLOR_DIVIDER
        })

        -- 图标
        local isc = "/luadb/img.png"
        if app.icon_path and io.exists(app.icon_path) then
            isc = app.icon_path
        end

        airui.image({
            parent = card, x = 12, y = 12, w = isz, h = isz, src = isc
        })

        -- 应用名称
        local ny = 15
        airui.label({
            parent = card,
            x = isz + 20,
            y = ny,
            w = cw - isz - 28,
            h = tfs + 4,
            text = app.title or app.name or "未知",
            font_size = tfs,
            color = COLOR_TEXT
        })

        -- 信息行：大小和下载量（格式：XXKB | ↓ xx次）
        local ioy = ny + tfs + 6
        local szt = (app.origin_size_kb and app.origin_size_kb ~= "") and (app.origin_size_kb .. "KB") or "未知"
        local dlt = (app.total_downloads and tostring(app.total_downloads)) or "0"
        local ift = string.format("%s | ↓ %s次", szt, dlt)
        airui.label({
            parent = card,
            x = isz + 20,
            y = ioy,
            w = cw - isz - 28,
            h = ifs + 4,
            text = ift,
            font_size = ifs,
            color = COLOR_TEXT_SECONDARY
        })

        -- 应用描述（动态行数）
        if mdl > 0 then
            local dsy = ioy + ifs + 8
            local dh = dfs * mdl + (mdl > 1 and 2 or 0)
            airui.label({
                parent = card,
                x = 12,
                y = dsy,
                w = cw - 24,
                h = dh,
                text = app.desc or "",
                font_size = dfs,
                color = COLOR_TEXT_SECONDARY
            })
        end

        -- 按钮（安装/更新/卸载）
        if app.installed then
            if app.has_update then
                local bw = math.min(70, (cw - 36) / 2)
                airui.button({
                    parent = card,
                    x = 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "更新",
                    font_size = bfs,
                    style = { bg_color = COLOR_ACCENT, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local mbx = airui.msgbox({
                            title = "确认更新",
                            text = "是否更新应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, lb)
                                if lb == "确定" then
                                    spd(app.title or app.name)
                                    sys.publish("APP_STORE_UPDATE", tostring(app.aid), app.url, app.title or app.name,
                                        cc, cs)
                                end
                                self:hide()
                            end
                        })
                        mbx:show()
                    end
                })
                airui.button({
                    parent = card,
                    x = 12 + bw + 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "卸载",
                    font_size = bfs,
                    style = { bg_color = COLOR_DANGER, pressed_bg_color = COLOR_DANGER, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local mbx = airui.msgbox({
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, lb)
                                if lb == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), cc, cs)
                                end
                                self:hide()
                            end
                        })
                        mbx:show()
                    end
                })
            else
                local bw = math.min(80, cw - 24)
                airui.button({
                    parent = card,
                    x = 12,
                    y = by,
                    w = bw,
                    h = bh,
                    text = "卸载",
                    font_size = bfs,
                    style = { bg_color = COLOR_DANGER, pressed_bg_color = COLOR_DANGER, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                    on_click = function()
                        local mbx = airui.msgbox({
                            title = "确认卸载",
                            text = "是否卸载应用 " .. (app.title or app.name) .. "？",
                            buttons = { "确定", "取消" },
                            on_action = function(self, lb)
                                if lb == "确定" then
                                    sys.publish("APP_STORE_UNINSTALL", tostring(app.aid), cc, cs)
                                end
                                self:hide()
                            end
                        })
                        mbx:show()
                    end
                })
            end
        else
            local bw = math.min(80, cw - 24)
            airui.button({
                parent = card,
                x = 12,
                y = by,
                w = bw,
                h = bh,
                text = "安装",
                font_size = bfs,
                style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 16, border_width = 0 },
                on_click = function()
                    local mbx = airui.msgbox({
                        title = "确认安装",
                        text = "是否安装应用 " .. (app.title or app.name) .. "？",
                        buttons = { "确定", "取消" },
                        on_action = function(self, lb)
                            if lb == "确定" then
                                spd(app.title or app.name)
                                sys.publish("APP_STORE_INSTALL", tostring(app.aid), app.url, app.title or app.name,
                                    cc, cs)
                            end
                            self:hide()
                        end
                    })
                    mbx:show()
                end
            })
        end
    end
end

-------------------------------------------------------------------------------
-- 消息回调
-------------------------------------------------------------------------------
local function oiu(ni)
    for aid, _ in pairs(ni) do
        lii[aid] = true
    end
end

local function olu(apps, pg)
    local hn = false
    local tn = cp
    local tl = 0
    if type(pg) == "table" then
        if type(pg.page) == 'number' then
            cp = pg.page
        end
        if type(pg.total_pages) == 'number' then
            tn = pg.total_pages
        elseif type(pg.total_pages) == 'number' then
            tn = pg.total_pages
        end
        if type(pg.total) == 'number' then
            tl = pg.total
        end
        if pg.has_more ~= nil then
            hn = (pg.has_more == true)
        else
            hn = (cp < tn)
        end
    end

    hm = hn
    if type(tn) ~= "number" then
        tn = 1
    end
    tp = math.max(tn, 1)
    upd()

    local ia = exapp.list_installed()

    for _, app in ipairs(apps) do
        local aid = tostring(app.aid)
        local ca = lii[aid]
        if ca ~= nil then
            app.installed = ca
            if ca and ia[aid] then
                local info = ia[aid]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            end
        else
            if ia[aid] then
                app.installed = true
                local info = ia[aid]
                if info and info.path then
                    app.path = info.path
                    app.icon_path = info.icon_path
                end
            else
                app.installed = false
            end
        end
    end
    if cc == "已安装" then
        local filtered = {}
        for _, app in ipairs(apps) do
            if app.installed then
                table.insert(filtered, app)
            end
        end
        if #filtered == 0 then
            return
        end
        apps = filtered
        tp = math.max(1, math.ceil(#filtered / plim))
        hm = false
    end
    ra(apps, hm)
end

local function opr(aid, pc, st)
    if pbar and pbl then
        pbar:set_value(pc)
        pbl:set_text(st or string.format("下载进度 %d%%", pc))
        if pc >= 100 then
            pbl:set_text("解压完成，请稍候...")
        end
    end
end

local function oad(aid, ac, sc)
    cpd()

    if sc then
        local an = nil
        local ia = exapp.list_installed()
        if ia[aid] then
            an = ia[aid].cn_name or ia[aid].name
        end

        local apps, more = exapp.get_current_list()
        if apps then
            local idx = nil
            for i, app in ipairs(apps) do
                if tostring(app.aid) == aid then
                    idx = i
                    break
                end
            end

            if idx then
                if ac == "install" then
                    apps[idx].installed = true
                    apps[idx].has_update = false
                elseif ac == "update" then
                    apps[idx].has_update = false
                    apps[idx].installed = true
                elseif ac == "uninstall" then
                    apps[idx].installed = false
                end
            end

            if cc == "已安装" then
                local filtered = {}
                for _, app in ipairs(apps) do
                    if app.installed then
                        table.insert(filtered, app)
                    end
                end
                if #filtered > 0 then
                    ra(filtered, false)
                end
            else
                ra(apps, more)
            end
        end

        sst(ac, an)

        local key = tostring(aid)
        if ac == "install" and sc then
            lii[key] = true
        elseif ac == "uninstall" and sc then
            lii[key] = false
        end
    end
end

local function oer(msg)
    cpd()
    local mbx = airui.msgbox({
        title = "错误",
        text = msg,
        buttons = { "确定" },
        on_action = function(self, lb) self:hide() end
    })
    mbx:show()
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function ocr()
    cl()
    cui()

    sys.subscribe("APP_STORE_LIST_UPDATED", olu)
    sys.subscribe("APP_STORE_PROGRESS", opr)
    sys.subscribe("APP_STORE_ERROR", oer)
    sys.subscribe("APP_STORE_ACTION_DONE", oad)
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", oiu)
    sys.subscribe("APP_STORE_ICON_READY", oir)

    sys.publish("APP_STORE_SYNC_INSTALLED")
    sys.publish("APP_STORE_GET_LIST", cc, cs, cp, plim, cq)
end

local function ods()
    sys.unsubscribe("APP_STORE_LIST_UPDATED", olu)
    sys.unsubscribe("APP_STORE_PROGRESS", opr)
    sys.unsubscribe("APP_STORE_ERROR", oer)
    sys.unsubscribe("APP_STORE_ACTION_DONE", oad)
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", oiu)
    sys.unsubscribe("APP_STORE_ICON_READY", oir)

    cpd()
    if sk then sk:destroy() end
    if mc then mc:destroy() end
end

local function ogf()
    local apps, more = exapp.get_current_list()
    if apps then
        if cc == "已安装" then
            local ia = exapp.list_installed()
            local filtered = {}
            for _, app in ipairs(apps) do
                local aid = tostring(app.aid)
                if ia[aid] then
                    app.installed = true
                    table.insert(filtered, app)
                end
            end
            if #filtered == 0 then
                return
            end
            ra(filtered, false)
        else
            ra(apps, more)
        end
    end
end

local function olf()
    lii = {}
end

local function oh()
    wid = exwin.open({
        on_create = ocr,
        on_destroy = ods,
        on_get_focus = ogf,
        on_lose_focus = olf,
    })
end

sys.subscribe("OPEN_APP_STORE_WIN", oh)
