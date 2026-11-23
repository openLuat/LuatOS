--[[
@module page_ktv
@summary AIR KTV 点歌系统 · 9 页面 + 顶栏/侧栏/迷你条 + 全部交互
         1:1 复刻 docs/index.html（1024×600）
         搜索页使用原生 airui.keyboard(mode="pinyin_26") + airui.textarea，
         自带中文候选栏，中英文/符号切换与退格由固件输入法处理。
]]

local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

local M = {}
local S = mock.S
local C = theme.C
local AL, AC, AR = theme.AL, theme.AC, theme.AR

local R = {}
local M_gen = 0
local M_clock = 0
local ensure_keyboard          -- 前向声明：懒加载原生键盘
local grad_bar                 -- 前向声明：渐变填充条
local grad_progress            -- 前向声明：青→黄进度渐变
local refresh_navbar           -- 前向声明：侧栏激活态

local function T(...)  return theme.txt(...) end
local function B(...)  return theme.box(...) end
local function BB(...) return theme.box_b(...) end
local function I(...)  return theme.icon(...) end
local function H(...)  return theme.hit(...) end
local function call(o,m,...) return theme.nilcall(o,m,...) end

-- 图标图元整体平移（ic_items 以 0,0 为原点，需要居中放进方块里）
local function offset_items(items,dx,dy)
    for i=1,#items do
        local it = items[i]
        if it.type=="line" then
            it.x1=it.x1+dx; it.x2=it.x2+dx; it.y1=it.y1+dy; it.y2=it.y2+dy
        elseif it.type=="rect" then
            it.x=it.x+dx; it.y=it.y+dy
        elseif it.type=="circle" then
            it.cx=it.cx+dx; it.cy=it.cy+dy
        end
    end
    return items
end

-- 半透明圆（图元层叠做光晕/纹理用，cl() 只支持不透明填充）
local function dot(cx,cy,r,col,opa)
    return {type="circle",cx=math.floor(cx),cy=math.floor(cy),r=math.floor(r),
        color=col,width=1,fill=true,fill_color=col,fill_opacity=opa or 60}
end

-- 侧栏图标配色：{上亮, 下深}，未激活时做竖向渐变底色
local NAV = {
    {id="home",name="推荐",ic="home",g={0x4F8CFF,0x3B6BE8}},
    {id="category",name="点歌",ic="cat",g={0xA179FF,0x7C4DF0}},
    {id="search",name="搜索",ic="search",g={0x3EE0D0,0x14B8C4}},
    {id="ordered",name="已点",ic="list",g={0x4A9BFF,0x2F77E8}},
    {id="settings",name="设置",ic="set",g={0xFFA95E,0xF07A28}},
}
local TILES = {
    {"category","歌名点歌","按曲风选歌","cat"},
    {"artist","歌手点歌","按歌手找歌","artist"},
    {"search","全能搜索","歌名 / 歌手","search"},
    {"rank","热门榜单","大家都在唱","rank"},
    {"playlist","精选歌单","场景推荐","playlist"},
    {"ordered","已点歌曲","","list"},
    {"playing","正在播放","播放控制","playing"},
    {"settings","系统设置","主题 / 音量","set"},
}
local FUNC = {
    {"next","切歌","next"},{"toggle","播放","play"},
    {"replay","重唱","replay"},{"origin","原唱","mic"},
    {"mute","静音","mute"},{"eq","调音","eq"},
    {"control","空调","control"},{"atmos","气氛","atmos"},
}

--------------------------------------------------------------------
-- 刷新调度
--------------------------------------------------------------------
local function refresh_page(p)
    local fn = R.refresh and R.refresh[p]
    if fn then
        local ok,e = pcall(fn)
        if not ok then pcall(log.error,"ktv","refresh "..tostring(p)..": "..tostring(e)) end
    end
end

local function refresh_all()
    for k,_ in pairs(R.scr or {}) do refresh_page(k) end
    refresh_page("mini")
    -- 深/浅色切换后侧栏图标颜色也要跟着换
    if refresh_navbar then refresh_navbar() end
end

function M.hide_toast()
    call(R.toast_bg,"set_hidden",true)
    call(R.toast_hit,"set_hidden",true)
    call(R.toast_mask,"set_hidden",true)
    call(R.toast_lb,"set_text","")
    R.toast_until = nil
    R.toast_shown = false
end

function M.toast(msg)
    if not R.toast_bg then
        if build_toast then pcall(build_toast, airui.screen) end
        if not R.toast_bg then return end
    end
    call(R.toast_lb,"set_text",tostring(msg or ""))
    call(R.toast_bg,"set_hidden",false)
    call(R.toast_hit,"set_hidden",false)
    if R.toast_mask then call(R.toast_mask,"set_hidden",false) end
    R.toast_shown = true
    R.toast_until = M_clock + 18
end

-- 强制整页重绘：页面容器连着设两次颜色（3% 混白 → 还原），同一帧内只留最终值，
-- 但脏区会让 LVGL 把整块区域连同子控件重画一遍，用来清切页/换主题留下的残影与文字彩边
local function force_redraw(o, base)
    if not o then return end
    base = base or C.bg
    call(o,"set_color",theme.mix(base,C.white,3/100),255)
    call(o,"set_color",base,255)
end
local function redraw_page(name)
    force_redraw(R.scr and R.scr[name])
end

function M.go(page)
    local map = {artist="category",rank="home",playlist="home",playing="home"}
    local nav = map[page] or page
    S.page = page
    if page ~= "playlist" then S.plDetail = -1 end
    -- 切页立即清掉 toast / 快捷功能浮层，避免遮罩残留在新页面上
    if R.toast_bg then M.hide_toast() end
    if S.funcPop then M.hide_funcpop() end

    -- 分帧补建期间用户提前点进某页：即时同步补建，避免空屏
    if not R.ready and R.builders then
        local names = R.names
        local idx = nil
        for i=1,#names do if names[i]==page then idx=i end end
        if idx and not R.built[idx] and R.builders[idx] then
            local ok,e = pcall(R.builders[idx], R.scr[page])
            if not ok then pcall(log.error,"ktv","late build "..page..": "..tostring(e)) end
            R.built[idx] = true
        end
    end

    for k,v in pairs(R.scr or {}) do call(v,"set_hidden",k ~= page) end
    -- 抹掉切页残影：页面容器按创建顺序叠放，切到 z 序更低的页时，旧页已画的像素没人覆盖
    redraw_page(page)
    if refresh_navbar then refresh_navbar(nav) end
    -- 进入搜索页不自动弹键盘；只有点击输入框才弹
    if R.kb then call(R.kb,"hide"); call(R.kb,"set_hidden",true) end
    if R.kb_hit then call(R.kb_hit,"set_hidden",false) end
    refresh_page(page)
    refresh_page("mini")
end

--------------------------------------------------------------------
-- 播放控制
--------------------------------------------------------------------
function M.add(i)
    if i == nil then return end
    for k=1,#S.ordered do
        if S.ordered[k].i == i then
            M.toast("《"..mock.song(i).n.."》已在点歌列表中")
            return
        end
    end
    S.ordered[#S.ordered+1] = {i=i,playing=false}
    M.toast("已添加《"..mock.song(i).n.."》到点歌列表")
    refresh_page("mini")
    if S.page=="home" or S.page=="ordered" or S.page=="playing" then refresh_page(S.page) end
end

function M.toggle_play()
    S.playing = not S.playing
    M.toast(S.playing and "继续播放" or "已暂停")
    refresh_page("playing"); refresh_page("mini"); refresh_page("funcpop")
end

function M.change(step)
    if #S.ordered == 0 then M.toast("点歌列表为空") return end
    local cur = 1
    for i=1,#S.ordered do if S.ordered[i].i==S.playIndex then cur=i break end end
    local nxt = ((cur-1+(step or 1)) % #S.ordered)+1
    for i=1,#S.ordered do S.ordered[i].playing = (i==nxt) end
    S.playIndex = S.ordered[nxt].i
    S.progress = 0
    S.play_sec = 0
    M.toast("播放："..mock.song(S.playIndex).n)
    refresh_page("playing"); refresh_page("mini"); refresh_page("funcpop")
end

function M.replay()
    S.progress = 0
    S.play_sec = 0
    M.toast("重唱《"..mock.song(S.playIndex).n.."》已从头开始")
    refresh_page("playing"); refresh_page("mini")
end

function M.func(v)
    if v=="next" then M.change(1); return end
    if v=="toggle" then M.toggle_play(); return end
    if v=="replay" then M.replay(); return end
    if v=="mute" then S.mute = not S.mute; M.toast(S.mute and "已静音" or "已取消静音")
    elseif v=="origin" then S.origin = not S.origin; M.toast(S.origin and "已切换原唱" or "已切换伴唱")
    elseif v=="atmos" then S.atmos = not S.atmos; M.toast(S.atmos and "氛围灯已开启" or "氛围灯已关闭")
    elseif v=="eq" then
        if S.eqOpen then M.close_modal()
        else S.eqOpen=true; S.acOpen=false; M.open_modal("eq") end
    elseif v=="control" then
        if S.acOpen then M.close_modal()
        else S.acOpen=true; S.eqOpen=false; M.open_modal("ac") end
    end
    refresh_page("playing"); refresh_page("funcpop")
end

--------------------------------------------------------------------
-- 滑杆（定点更新，避免一次触摸刷多页）
--------------------------------------------------------------------
local function slider(parent,x,y,w,act,val)
    local ref = {}
    local cb = function(_, v)
        v = tonumber(v)
        if not v and ref.sl then
            pcall(function() v = ref.sl:get_value() end)
            v = tonumber(v)
        end
        if not v then return end
        M.apply_slider(act, v)
    end
    local sl = theme.slider(parent,x,y,w,8,val,cb)
    ref.sl = sl
    return sl
end

function M.apply_slider(act,pct)
    pct = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    if act=="seek" then
        S.progress = pct
        local sk = mock.song(S.playIndex)
        S.play_sec = math.floor(mock.durSec(sk.d)*pct/100)
        local s = sk
        if s then
            local total = mock.durSec(s.d)
            local pw = math.floor(680*pct/100)
            -- 拖动时也用青→黄渐变，别再用纯蓝（图 3 蓝色进度条反馈）
            grad_progress(R.play_fill,680,pct,8,true)
            call(R.play_knob,"set_pos",172+pw-7,68)
            grad_progress(R.mini_fill,238,pct,10)
            local t = mock.fmt(S.play_sec)
            call(R.play_time,"set_text",t.." / "..s.d)
            call(R.mini_time,"set_text",t.." / "..s.d)
        end
    elseif act=="volume" or act=="setVol" then
        S.volume = pct
        local vw = math.floor(240*pct/100)
        grad_progress(R.vol_fill,240,pct,8,true)
        call(R.vol_knob,"set_pos",462+vw-7,122)
        grad_progress(R.set_vol_fill,394,pct,10)
        local eq = R.eq
        if eq then
            grad_bar(eq.fill[3],456,pct,14)
            call(eq.val[3],"set_text",pct.."%")
        end
        call(R.vol_pct,"set_text",pct.."%")
        call(R.set_vol_lb,"set_text",pct.."%")
    elseif act=="setBri" then
        S.brightness = pct
        grad_progress(R.set_bri_fill,394,pct,10)
        call(R.set_bri_lb,"set_text",pct.."%")
    elseif act=="pitch" or act=="micVol" then
        local i,key = (act=="pitch") and 1 or 2, (act=="pitch") and "pitch" or "micVol"
        S[key] = pct
        local eq = R.eq
        if eq then
            grad_bar(eq.fill[i],456,pct,14)
            call(eq.val[i],"set_text",pct..((i==1) and "" or "%"))
        end
    end
end

function M.set_theme(key)
    if key==S.theme then M.toast("当前已选中该配色") return end
    S.theme = key
    theme.apply(S.mode,S.theme); C = theme.C
    theme.defer(function()
        theme.recolor(); refresh_all()
        -- 换色后整页重绘，避免旧颜色的抗锯齿边留在文字/图标周围（彩边）
        redraw_page(S.page); force_redraw(R.mini_panel, C.mini)
    end)
    M.toast("配色已切换")
end
function M.set_mode(mode)
    if mode==S.mode then M.toast(mode=="dark" and "当前已是深色模式" or "当前已是浅色模式") return end
    S.mode = mode
    theme.apply(S.mode,S.theme); C = theme.C
    theme.defer(function()
        theme.recolor(); refresh_all()
        redraw_page(S.page); force_redraw(R.mini_panel, C.mini)
    end)
    M.toast(mode=="dark" and "已切换深色模式" or "已切换浅色模式")
end

--------------------------------------------------------------------
-- 顶栏 / 侧栏 / 页头
--------------------------------------------------------------------
local function build_top(root)
    local p = B(root,0,0,1024,58,C.topbar,0)
    B(p,0,56,1024,2,C.glow,0)
    B(p,16,12,34,34,C.blue,9)
    I(p,22,17,22,22,"note",C.white,2)
    T(p,60,10,180,38,"AIR KTV",C.text,19,AL)
    R.top_date = T(p,520,12,210,34,"----",C.sub,16,AR)
    R.top_clock = T(p,736,10,118,38,"00:00:00",C.text,20,AR)
    -- 空 container 作药丸底（子 label 挂顶栏，不塞进 container → 无滚动条且随主题变色）
    B(p,860,13,148,32,C.card,16)
    T(p,866,13,62,32,"包厢",C.sub,16,AL)
    T(p,926,13,78,32,"VIP 088",C.cyan,16,AC)
end

local function refresh_clock()
    local function p2(n) return (n<10 and "0" or "")..n end
    local wk = {"星期日","星期一","星期二","星期三","星期四","星期五","星期六"}
    local t = os.date("*t")
    if not t.year or t.year < 2024 then
        -- RTC 未校准：从 2026-11-18(星期三) 15:03:00 起，按运行时长手算，避开时区差异
        local sec = 15*3600 + 3*60 + math.floor(M_clock/10)
        local day = 18 + math.floor(sec/86400)
        sec = sec % 86400
        local hour = math.floor(sec/3600)
        local min  = math.floor((sec%3600)/60)
        local s    = sec%60
        local mon, mday = 11, day
        local mdays = {31,28,31,30,31,30,31,31,30,31,30,31}
        while mday > mdays[mon] do mday = mday - mdays[mon]; mon = mon + 1
            if mon > 12 then mon = 1 end end
        local w = ((4 - 1 + (day - 18)) % 7) + 1   -- 2026-11-18 是星期三(wday=4)
        call(R.top_clock,"set_text",p2(hour)..":"..p2(min)..":"..p2(s))
        call(R.top_date,"set_text",string.format("2026-%02d-%02d %s",mon,mday,wk[w]))
        return
    end
    call(R.top_clock,"set_text",p2(t.hour)..":"..p2(t.min)..":"..p2(t.sec))
    call(R.top_date,"set_text",string.format("%04d-%02d-%02d %s",t.year,t.month,t.day,wk[t.wday]))
end

local function build_nav(root)
    B(root,0,58,124,458,C.nav,0)
    R.nav_bg,R.nav_lb,R.nav_ic,R.nav_g,R.nav_bd = {},{},{},{},{}
    for i=1,#NAV do
        local y = 58+(i-1)*83
        -- 不用 container 边框：未激活时边框色和底色差一点就会露出灰框（图 1 的问题）
        -- 改成独立的描边图元层，只有激活项才画蓝框
        local bg = B(root,8,y,100,74,C.nav,16)
        -- 描边层要建在图标之前，否则内圈填充会盖住图标
        local bd = theme.shape(bg,0,0,100,74)
        -- 图标挂单个 shape：未激活=彩色圆角方块+白线条，激活=纯线条（对齐设计稿）
        local sh = theme.shape(bg,28,8,44,44)
        local lb = T(bg,0,52,100,22,NAV[i].name,C.sub,17,AC)
        R.nav_bg[i],R.nav_lb[i],R.nav_ic[i],R.nav_g[i],R.nav_bd[i] = bg,lb,sh,NAV[i].g[1],bd
        -- 侧栏自带激活态高亮，按下不再叠透明白框
        H(root,8,y,100,74,function() M.go(NAV[i].id) end,true)
    end
end

-- 侧栏激活态：激活项深色胶囊 + 亮蓝文字 + 纯色线条图标；未激活为彩色方块图标
refresh_navbar = function(cur)
    if not R.nav_bg then return end
    cur = cur or S.page
    local map = {artist="category",rank="home",playlist="home",playing="home"}
    cur = map[cur] or cur
    for i=1,#NAV do
        local on = (NAV[i].id == cur)
        -- 激活胶囊：偏暗的海军蓝（比 C.acw 更沉，贴近设计稿）+ 亮蓝细描边
        call(R.nav_bg[i],"set_color",on and theme.mix(C.blue,C.bg,10/100) or C.nav,255)
        -- 2px 蓝框：外圈实心蓝 + 内圈回填胶囊底色，比 stroke-only 图元可靠
        theme.put(R.nav_bd[i], on and {
            theme.rc(1,1,98,72,C.blue,15),
            theme.rc(3,3,94,68,theme.mix(C.blue,C.bg,10/100),13),
        } or {})
        -- 激活项：白色文字（设计稿），不再用蓝字
        call(R.nav_lb[i],"set_color",on and C.white or C.sub)
        R.nav_key = R.nav_key or {}
        local key = tostring(on)..S.mode
        if R.nav_key[i] ~= key then
            R.nav_key[i] = key
            if on then
                theme.put(R.nav_ic[i], offset_items(
                    theme.ic_items(NAV[i].ic,26,26,S.mode=="dark" and 0xFFFFFF or C.blue,2),9,9))
            else
                -- 未激活：上亮下深的彩色圆角方块（设计稿的渐变图标底）+ 白线条
                local g = NAV[i].g
                local items = {
                    theme.rc(0,0,44,44,g[2],14),
                    theme.rc(0,0,44,31,theme.mix(g[1],g[2],40/100),14),
                    theme.rc(0,0,44,17,g[1],14),
                }
                local ls = offset_items(theme.ic_items(NAV[i].ic,26,26,0xFFFFFF,2),9,9)
                for k=1,#ls do items[#items+1] = ls[k] end
                theme.put(R.nav_ic[i], items)
            end
        end
    end
end

local function head(p,title,desc,right,back)
    local x = 16
    if back then
        local b = BB(p,x,14,34,32,C.card,9,C.line,1)
        I(b,8,6,18,18,"back",C.sub,2)
        H(p,x,14,34,32,function() M.go("home") end)
        x = x+44
    end
    B(p,x,21,3,18,C.cyan,2)
    T(p,x+12,14,200,30,title,C.text,19,AL)
    if desc then T(p,x+220,16,260,28,desc,C.sub,16,AL) end
    -- 右上角说明文字：留足宽度并略缩字号，避免被页面右边缘裁掉
    if right then T(p,460,17,408,26,right,C.sub,15,AR) end
end

--------------------------------------------------------------------
-- 首页
--------------------------------------------------------------------
local function build_home(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"欢迎光临","今晚尽兴欢唱","点击磁贴开始欢唱",false)

    -- 主推卡：蓝→紫→品红横向渐变（4 层圆角矩形叠加近似），右侧叠淡色光晕
    local fbg = theme.shape(p,16,54,868,96)
    theme.put(fbg,{
        theme.rc(0,0,868,96,0xA82B8C,14),
        theme.rc(0,0,706,96,0x8B27C4,14),
        theme.rc(0,0,486,96,0x5C2BD6,14),
        theme.rc(0,0,262,96,0x2434D6,14),
        dot(760,48,64,0xD855B4,44),
        dot(760,48,40,0xC746A6,40),
        dot(760,48,18,0xB63C9A,36),
        theme.ln(818,34,832,48,0xF0C4EA,3),
        theme.ln(832,48,818,62,0xF0C4EA,3),
    })
    -- 内容层：透明容器盖在渐变之上，子控件照常挂
    local f = airui.container({parent=p,x=16,y=54,w=868,h=96,color=C.bg,radius=0})
    theme.nilcall(f,"set_color",C.bg,0)
    local hcov = theme.songcover(f,10,9,78,0,10,0x477BFF)
    theme.songcover_set(hcov, 0, "孤勇者")
    -- "今日主打" 胶囊：青绿渐变 + 白字
    local tg = theme.shape(f,100,13,80,24)
    theme.put(tg,{theme.rc(0,0,80,24,0x2FD9A6,12),theme.rc(0,0,52,24,0x35E8B0,12)})
    T(f,100,13,80,24,"今日主打",0xFFFFFF,15,AC)
    T(f,100,41,480,30,"孤勇者",C.white,21,AL)
    T(f,100,70,620,22,"陈奕迅  ·  高品质曲库，一键点唱",0xDCE4FF,16,AL)
    local ab = B(f,806,46,44,44,C.blue,12)
    I(ab,12,12,20,20,"plus",C.white,2)
    H(f,806,46,44,44,function() M.add(0) end)

    B(p,16,166,6,6,C.cyan,3)
    T(p,28,158,260,22,"快捷入口",C.text,16,AL)
    T(p,600,158,284,22,"常用功能一屏直达",C.sub,16,AR)

    R.tile_cnt = {}
    local TW,TH,GX,GY = 202,116,18,14
    for i=1,8 do
        local col,row = (i-1)%4, math.floor((i-1)/4)
        local x,y = 22+col*(TW+GX), 186+row*(TH+GY)
        local g = mock.TILE_GRADS[i]
        -- 用 shape 画圆角底色：上亮下深三层叠加近似渐变
        local bg = theme.shape(p,x,y,TW,TH)
        theme.put(bg,{
            theme.rc(0,0,TW,TH,g[2],18),
            theme.rc(0,0,TW,math.floor(TH*72/100),theme.mix(g[1],g[2],38/100),18),
            theme.rc(0,0,TW,math.floor(TH*40/100),g[1],18),
            dot(TW-26,20,46,0xFFFFFF,18),
        })
        -- 图标底：半透明白圆角方块 + 纯白线条图标（对齐设计稿）
        theme.box_a(p,x+(TW-56)/2,y+8,56,56,0xFFFFFF,18,50)
        local ic = theme.shape(p,x+(TW-56)/2,y+8,56,56)
        theme.put(ic, offset_items(theme.ic_items(TILES[i][4],30,30,0xFFFFFF,2),13,13))
        T(p,x,y+66,TW,24,TILES[i][2],C.white,20,AC)
        R.tile_cnt[i] = T(p,x,y+92,TW,18,TILES[i][3],0xE4EBFF,15,AC)
        H(p,x,y,TW,TH,function() M.go(TILES[i][1]) end)
    end
end
local function refresh_home()
    call(R.tile_cnt[6],"set_text",#S.ordered.." 首待唱")
end

--------------------------------------------------------------------
-- 歌曲分类
--------------------------------------------------------------------
local function build_category(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"歌曲分类","按风格与语种选歌","共 36 首歌曲",false)

    R.cat_btn = {}
    for i=1,#mock.CATS do
        local y = 54+(i-1)*48
        R.cat_btn[i] = BB(p,16,y,104,42,C.card,10,C.line,1)
        T(R.cat_btn[i],4,5,96,32,mock.CATS[i],C.sub,16,AC)
        H(p,16,y,104,42,function() S.cat=i; S.cat_song_page=1; refresh_page("category") end)
    end

    R.cat_card = {}
    local CW,CH,GX,GY = 214,116,20,16
    for i=1,9 do
        local col,row = (i-1)%3, math.floor((i-1)/3)
        local x,y = 138+col*(CW+GX), 56+row*(CH+GY)
        -- 空 container 组包住整卡：空位时整组移出屏幕，不留无色块
        local grp = airui.container({parent=p,x=x,y=y,w=CW,h=CH,color=C.bg,radius=0})
        theme.nilcall(grp,"set_color",C.bg,0)
        local card = theme.shape(grp,0,0,CW,CH)
        local cov = theme.songcover(grp,8,8,60,i,10)
        local mark = cov.mk
        local nm = T(grp,76,10,CW-84,26,"",C.text,16,AL)
        local ar = T(grp,76,42,CW-84,22,"",C.sub,16,AL)
        local ab = B(grp,CW-44,76,34,34,C.blue,9)
        I(ab,7,7,20,20,"plus",C.white,2)
        R.cat_card[i] = {card=card,nm=nm,ar=ar,cov=cov,mark=mark,grp=grp,x=x,y=y}
        H(grp,CW-44,76,34,34,function()
            local it = R.cat_card[i].idx
            if it then M.add(it) end
        end)
    end
end
local function refresh_category()
    local list = {}
    for i=1,#mock.SONGS do
        local s = mock.SONGS[i]
        for k=1,#s.c do if s.c[k]==mock.CATS[S.cat] then list[#list+1]=i-1 end end
    end
    if #list==0 then for i=0,7 do list[#list+1]=i end end
    local pages = math.max(1, math.ceil(#list/9))
    S.cat_song_page = math.max(1, math.min(pages, S.cat_song_page or 1))
    local offset = (S.cat_song_page-1)*9
    for i=1,9 do
        local it = R.cat_card[i]
        local idx = list[offset+i]
        it.idx = idx
        if idx then
            call(it.grp,"set_pos",it.x,it.y)
            call(it.grp,"set_hidden",false)
            theme.put(it.card,{
                theme.rc(0,0,214,116,C.card,12),
                theme.rc(0,0,214,116,C.line,12),
                theme.rc(1,1,212,114,C.card,11),
            })
            local s = mock.song(idx)
            call(it.nm,"set_text",s.n)
            call(it.ar,"set_text",s.a.." - "..s.d)
            theme.songcover_set(it.cov, idx, s.n)
        else
            -- 无歌曲的卡位直接隐藏（不用负坐标移出屏幕，否则容器内容溢出会冒出滚动条）
            call(it.grp,"set_hidden",true)
        end
    end
    for i=1,#R.cat_btn do
        call(R.cat_btn[i],"set_color",i==S.cat and C.acw or C.card,255)
    end
end

--------------------------------------------------------------------
-- 歌手分类
--------------------------------------------------------------------
local function build_artist(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"歌手分类","按歌手查找歌曲","华语 / 欧美 / 日韩",true)

    T(p,16,54,80,26,"歌手类型",C.sub,16,AL)
    R.af_btn = {}
    local types = {"全部","男","女","组合"}
    for i=1,#types do
        local x = 96+(i-1)*72
        local lb = theme.pill(p,x,52,66,30,types[i],16,function()
            S.artistFilter = types[i]; S.artist_page=1; refresh_page("artist")
        end,false)
        R.af_btn[i] = lb
    end
    -- 拼音首字母筛选项："全部"胶囊 + A~Z（对齐设计稿第三行）
    R.al_btn = {}
    local ay = 86
    local allw = 60
    local ab = B(p,16,ay,allw,28,C.blue,8)
    local alb = T(ab,0,0,allw,28,"全部",0xFFFFFF,14,AC)
    R.al_all, R.al_all_lb = ab, alb
    H(p,16,ay,allw,28,function() S.artistLetter="全部"; refresh_page("artist") end)
    local ax0 = 16+allw+8
    local aw = math.floor((884-ax0)/26)
    for i=1,26 do
        local ch = string.char(64+i)
        local x = ax0+(i-1)*aw
        local lb = T(p,x,ay,aw,28,ch,C.sub,14,AC)
        R.al_btn[#R.al_btn+1] = {lb=lb,v=ch}
        H(p,x,ay,aw,28,function() S.artistLetter=ch; refresh_page("artist") end)
    end

    R.artist_card = {}
    R.artist_pos = {}
    -- 6 列 x 3 行：一屏放下全部 18 位歌手，"全部"里男/女/组合都看得到，无需翻页
    for i=1,18 do
        local col,row = (i-1)%6, math.floor((i-1)/6)
        local x,y = 18+col*146, 124+row*112
        R.artist_pos[i] = {x,y}
        -- 卡底用带边框 container：深/浅色由主题自动换（图 3 深卡 / 图 4 白卡细边）
        local card = BB(p,x,y,138,104,C.card,12,C.line,1)
        local g = mock.gradient(i+4)
        -- 头像圆单独一个 shape，颜色固定为歌曲渐变色，不随主题变化
        -- 内层叠加两层淡色同心圆，做出设计稿那种涟漪质感
        local cov = theme.shape(p,x+37,y+2,64,64)
        theme.put(cov,{
            theme.cl(32,32,32,g[1]),
            theme.cl(32,32,24,theme.mix(0xFFFFFF,g[1],14/100)),
            theme.cl(32,32,16,theme.mix(0xFFFFFF,g[1],22/100)),
        })
        local grp = airui.container({parent=p,x=x,y=y,w=138,h=104,color=C.bg,radius=0})
        theme.nilcall(grp,"set_color",C.bg,0)
        local ch = theme.first_char(mock.ARTISTS[i].n)
        -- 圆内首字：取歌手名第一个字（凤凰传奇 -> 凤），垂直居中于圆心
        local mk = T(grp,37,17,64,34,ch,0xFFFFFF,27,AC)
        T(grp,0,68,138,18,mock.ARTISTS[i].n,C.blue,15,AC)
        T(grp,0,85,138,16,mock.ARTISTS[i].c.." 首歌曲",C.sub,14,AC)
        R.artist_card[i] = {sh=card,grp=grp,mk=mk,ch=ch,cov=cov}
        H(grp,0,0,138,104,function()
            M.toast(mock.ARTISTS[i].n.." - 共 "..mock.ARTISTS[i].c.." 首可点歌曲")
        end)
    end
end
local function refresh_artist()
    local types = {"全部","男","女","组合"}
    for i=1,4 do
        local on = S.artistFilter==types[i]
        call(R.af_btn[i],"set_color",on and C.white or C.sub)
    end
    for _,e in ipairs(R.al_btn) do
        call(e.lb,"set_color",S.artistLetter==e.v and C.white or C.sub)
    end
    -- "全部"胶囊：选中时蓝底白字，未选时暗底灰字
    if R.al_all then
        local on = (S.artistLetter=="全部")
        call(R.al_all,"set_color",on and C.blue or C.card,255)
        call(R.al_all_lb,"set_color",on and 0xFFFFFF or C.sub)
    end
    for k=1,4 do if types[k]==S.artistFilter then S.artistTypeIdx=k end end
    -- 一屏 18 个（6x3），筛选结果直接全部铺开，"全部"即男+女+组合共 18 位
    S.artist_page = 1
    local shown = 0
    for i=1,18 do
        local a = mock.ARTISTS[i]
        local show = (S.artistFilter=="全部" or a.t==S.artistFilter) and
                     (S.artistLetter=="全部" or a.l==S.artistLetter)
        local it = R.artist_card[i]
        if show then
            local col,row = shown%6, math.floor(shown/6)
            local nx,ny = 18+col*146, 124+row*112
            call(it.grp,"set_pos",nx,ny)
            call(it.sh,"set_pos",nx,ny)
            call(it.cov,"set_pos",nx+37,ny+2)
            call(it.grp,"set_hidden",false)
            call(it.sh,"set_hidden",false)
            call(it.cov,"set_hidden",false)
            -- 圆内首字：深浅色都显示
            call(it.mk,"set_text", it.ch)
        else
            -- 只隐藏不移出屏幕：负坐标会让页面内容溢出、右侧冒出滚动条
            call(it.grp,"set_hidden",true)
            call(it.sh,"set_hidden",true)
            call(it.cov,"set_hidden",true)
        end
        if show then shown = shown + 1 end
    end
end

--------------------------------------------------------------------
-- 搜索：原生 textarea + pinyin_26 键盘
--------------------------------------------------------------------
local function build_search(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"歌曲搜索","输入歌名 / 歌手 / 拼音首字母",nil,true)

    BB(p,16,54,684,48,C.input,10,C.line,1)
    I(p,28,68,22,22,"search",C.sub,2)
    -- 原生输入框：加宽填满边框（52..688），去掉右侧空白
    R.ta = airui.textarea({
        parent=p, x=52, y=65, w=636, h=38,
        max_len=64, text="", placeholder="输入歌名 / 歌手 / 拼音",
        on_text_change=function(self)
            S.query = self:get_text() or ""
            refresh_page("search")
        end,
    })
    if R.ta then
        local st = {radius=8,bg_color=C.input,text_color=C.text,font_size=20}
        pcall(R.ta.set_style,R.ta,st)
    end
    -- 点击输入框才弹键盘：热区先挡着，点击后建键盘并隐藏热区，露出 textarea 输入
    R.kb_hit = H(p,52,59,636,48,function()
        if ensure_keyboard then pcall(ensure_keyboard) end
        if R.kb then
            call(R.kb,"show"); call(R.kb,"set_hidden",false)
        end
        call(R.kb_hit,"set_hidden",true)
        call(R.kb_tip,"set_text","")
    end)

    local sb = B(p,704,59,180,48,C.blue,10)
    I(sb,46,12,24,24,"search",C.white,2)
    T(sb,80,8,90,32,"搜索",C.white,20,AL)
    H(p,704,59,180,48,function()
        local n = #mock.search(S.query)
        M.toast(n>0 and ("找到 "..n.." 首相关歌曲") or "没有找到相关歌曲")
    end)

    local rb = BB(p,16,112,868,332,C.card,12,C.line,1)
    T(rb,14,8,300,26,"搜索结果",C.sub,19,AL)
    R.res_row = {}
    for i=1,4 do
        local y = 38+(i-1)*72
        local row = B(rb,6,y,856,66,i%2==0 and C.card2 or C.card,8)
        T(row,8,18,30,28,tostring(i),C.sub,17,AC)
        local cov = theme.songcover(row,44,7,52,i,8)
        local mk = cov.mk
        local nm = T(row,108,8,600,26,"",C.text,19,AL)
        local ar = T(row,108,34,600,22,"",C.sub,17,AL)
        local ab = B(row,812,15,34,34,C.blue,8)
        I(ab,7,7,20,20,"plus",C.white,2)
        R.res_row[i] = {row=row,nm=nm,ar=ar,cov=cov,mk=mk,idx=nil}
        H(row,812,15,34,34,function()
            local it = R.res_row[i].idx
            if it then M.add(it) end
        end)
    end
    R.res_empty = T(rb,10,150,848,44,"没有找到相关歌曲，换个关键词试试",C.sub,22,AC)

    -- 原生键盘很重（40+ 按键控件），改为首次进搜索页时才建
    R.kb_tip = T(p,320,180,520,40,"",C.sub,16,AC)
end

ensure_keyboard = function()
    if R.kb or not R.kb_tip then return end
    -- 必须全宽贴底：原生键盘候选栏是屏幕级布局，窄键盘会导致候选栏与主体错位、界面撕裂
    local ok, kb = pcall(airui.keyboard, {
        x=0, y=-20, w=1024, h=250,
        mode="pinyin_26",
        auto_hide=true,
        preview=false,
        on_commit=function(self) if self and self.hide then self:hide() end end,
    })
    if ok and kb then
        R.kb = kb
        if R.ta and R.ta.attach_keyboard then pcall(R.ta.attach_keyboard,R.ta,kb) end
        call(R.kb_tip,"set_text","")
    else
        call(R.kb_tip,"set_text","当前固件不支持输入键盘")
    end
end

local function refresh_search()
    local res = mock.search(S.query)
    call(R.res_empty,"set_text",#res>0 and "" or "没有找到相关歌曲，换个关键词试试")
    for i=1,4 do
        local it = R.res_row[i]
        local idx = res[i]
        it.idx = idx
        if idx then
            local s = mock.song(idx)
            call(it.row,"set_pos",6,36+(i-1)*72)
            call(it.row,"set_hidden",false)
            call(it.nm,"set_text",s.n)
            call(it.ar,"set_text",s.a)
            theme.songcover_set(it.cov, idx, s.n)
        else
            -- 无结果的空行直接隐藏（不用负坐标，避免容器溢出出现滚动条）
            call(it.row,"set_hidden",true)
            call(it.nm,"set_text","")
            call(it.ar,"set_text","")
            call(it.mk,"set_text","")
        end
    end
end

--------------------------------------------------------------------
-- 已点歌曲
--------------------------------------------------------------------
local function build_ordered(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"已点歌曲","点歌队列管理",nil,true)
    R.order_page = 1
    T(p,700,16,40,28,"<",C.sub,22,AC)
    H(p,690,12,56,34,function() R.order_page=math.max(1,R.order_page-1); refresh_page("ordered") end)
    R.order_pg = T(p,748,16,80,28,"1/2",C.cyan,16,AC)
    T(p,830,16,40,28,">",C.sub,22,AC)
    H(p,820,12,56,34,function() R.order_page=R.order_page+1; refresh_page("ordered") end)

    local sb = BB(p,16,54,868,56,C.card,12,C.line,1)
    R.sum_cnt = T(sb,16,12,180,32,"",C.sub,19,AL)
    R.sum_min = T(sb,210,12,200,32,"",C.sub,19,AL)
    R.sum_cur = T(sb,420,12,240,32,"",C.cyan,19,AL)
    local cb = B(sb,716,10,140,36,C.func,9)
    T(cb,16,4,120,28,"清空列表",C.del,16,AC)
    H(sb,716,10,140,36,function()
        S.ordered = {}
        M.toast("点歌列表已清空")
        refresh_page("ordered"); refresh_page("mini")
    end)

    R.order_row = {}
    for i=1,5 do
        local y = 122+(i-1)*66
        local row = airui.container({parent=p,x=16,y=y,w=868,h=58,color=C.bg,radius=0})
        theme.nilcall(row,"set_color",C.bg,0)
        local bgs = theme.shape(row,0,0,868,58)
        theme.put(bgs,{
            theme.rc(0,0,868,58,C.card,10),
            theme.rc(0,0,868,58,C.line,10),
            theme.rc(1,1,866,56,C.card,9),
        })
        local num = T(row,8,12,30,32,"",C.sub,19,AC)
        local cov = theme.songcover(row,44,6,46,i,7)
        local mk = cov.mk
        local nm = T(row,100,4,320,26,"",C.text,20,AL)
        local ar = T(row,100,30,320,24,"",C.sub,18,AL)
        local st = T(row,470,12,150,34,"待唱",C.sub,20,AC)
        local pb = B(row,700,7,44,44,C.card2,9); I(pb,12,12,20,20,"pin",C.sub,2)
        local db = B(row,772,7,44,44,C.card2,9); I(db,12,12,20,20,"trash",C.del,2)
        R.order_row[i] = {row=row,num=num,nm=nm,ar=ar,st=st,cov=cov,mk=mk}
        H(row,700,7,44,44,function()
            local idx = (R.order_page-1)*5+i
            local d = S.ordered[idx]
            if not d then return end
            if idx==1 then M.toast("该歌曲已在首位") return end
            local it = table.remove(S.ordered,idx)
            table.insert(S.ordered,1,it)
            M.toast("已置顶《"..mock.song(it.i).n.."》")
            refresh_page("ordered")
        end)
        H(row,772,7,44,44,function()
            local idx = (R.order_page-1)*5+i
            local d = S.ordered[idx]
            if not d then return end
            table.remove(S.ordered,idx)
            M.toast("已删除《"..mock.song(d.i).n.."》")
            refresh_page("ordered"); refresh_page("mini")
        end)
    end
    R.order_empty = T(p,16,240,868,44,"点歌列表为空，去挑几首喜欢的歌吧",C.sub,22,AC)
end
local function refresh_ordered()
    local total = 0
    for _,o in ipairs(S.ordered) do total = total+mock.durSec(mock.song(o.i).d) end
    call(R.sum_cnt,"set_text","已点 "..#S.ordered.." 首")
    call(R.sum_min,"set_text","预计时长 "..math.floor(total/60+50/100).." 分钟")
    local cur = mock.song(S.playIndex)
    call(R.sum_cur,"set_text","当前演唱 "..(cur and cur.n or "无"))
    local pages = math.max(1, math.ceil(#S.ordered/5))
    R.order_page = math.max(1, math.min(R.order_page,pages))
    call(R.order_pg,"set_text",R.order_page.."/"..pages)
    call(R.order_empty,"set_text",#S.ordered>0 and "" or "点歌列表为空，去挑几首喜欢的歌吧")
    for i=1,5 do
        local it = R.order_row[i]
        local idx = (R.order_page-1)*5+i
        local o = S.ordered[idx]
        if o then
            -- 有数据：移回原位并清空隐藏
            call(it.row,"set_pos",16,122+(i-1)*66)
            call(it.row,"set_hidden",false)
            local s = mock.song(o.i)
            call(it.num,"set_text",tostring(idx))
            call(it.nm,"set_text",s.n)
            call(it.ar,"set_text",s.a)
            call(it.st,"set_text",o.playing and "正在播放" or "待唱")
            call(it.st,"set_color",o.playing and C.cyan or C.sub)
            call(it.row,"set_color",o.playing and C.acw or C.card,255)
            theme.songcover_set(it.cov, o.i, s.n)
        else
            -- 无数据：直接隐藏，不显示空壳（不自行补充空白）
            call(it.row,"set_hidden",true)
        end
    end
end

--------------------------------------------------------------------
-- 排行榜
--------------------------------------------------------------------
local function build_rank(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"排行榜","大家都在点",nil,true)
    R.rank_page = 1
    T(p,700,16,40,28,"<",C.sub,22,AC)
    H(p,690,12,56,34,function() R.rank_page=math.max(1,R.rank_page-1); refresh_page("rank") end)
    R.rank_pg = T(p,748,16,80,28,"1/2",C.cyan,16,AC)
    T(p,830,16,40,28,">",C.sub,22,AC)
    H(p,820,12,56,34,function() R.rank_page=R.rank_page+1; refresh_page("rank") end)

    R.rank_chip = {}
    for i=1,#mock.RANKS do
        local x = 16+(i-1)*196
        local lb = theme.pill(p,x,52,188,36,mock.RANKS[i].name,16,function()
            S.rank = mock.RANKS[i].name; R.rank_page=1; refresh_page("rank")
        end,false)
        R.rank_chip[i] = lb
    end

    R.rank_row = {}
    for i=1,5 do
        local y = 100+(i-1)*72
        local row = airui.container({parent=p,x=16,y=y,w=868,h=64,color=C.bg,radius=0})
        theme.nilcall(row,"set_color",C.bg,0)
        local bgs = theme.shape(row,0,0,868,64)
        theme.put(bgs,{
            theme.rc(0,0,868,64,C.card,11),
            theme.rc(0,0,868,64,C.line,11),
            theme.rc(1,1,866,62,C.card,10),
        })
        local rn = T(row,8,10,40,40,"",C.sub,22,AC)
        local cov = theme.songcover(row,56,9,44,i,8)
        local mk = cov.mk
        local nm = T(row,110,6,420,28,"",C.text,18,AL)
        local ar = T(row,110,34,420,22,"",C.sub,16,AL)
        local du = T(row,620,16,100,28,"",C.sub,16,AR)
        local ab = B(row,776,12,38,38,C.blue,9)
        I(ab,9,9,20,20,"plus",C.white,2)
        R.rank_row[i] = {row=row,rn=rn,nm=nm,ar=ar,du=du,cov=cov,mk=mk,idx=nil}
        H(row,776,12,38,38,function()
            local it = R.rank_row[i].idx
            if it then M.add(it) end
        end)
    end
end
local function refresh_rank()
    for i=1,#mock.RANKS do
        call(R.rank_chip[i],"set_color",mock.RANKS[i].name==S.rank and C.white or C.sub)
    end
    local ids = mock.rankList()
    local pages = math.max(1, math.ceil(#ids/5))
    R.rank_page = math.max(1, math.min(R.rank_page,pages))
    call(R.rank_pg,"set_text",R.rank_page.."/"..pages)
    for i=1,5 do
        local it = R.rank_row[i]
        local n = (R.rank_page-1)*5+i
        local idx = ids[n]
        it.idx = idx
        if idx then
            call(it.row,"set_pos",16,100+(i-1)*72)
            call(it.row,"set_hidden",false)
            local s = mock.song(idx)
            call(it.rn,"set_text",tostring(n))
            call(it.nm,"set_text",s.n)
            call(it.ar,"set_text",s.a)
            call(it.du,"set_text",s.d)
            call(it.rn,"set_color",n==1 and C.rank1 or (n==2 and C.rank2 or (n==3 and C.rank3 or C.sub)))
            theme.songcover_set(it.cov, idx, s.n)
        else
            -- 翻页后超出数据的行直接隐藏，不显示空壳
            call(it.row,"set_hidden",true)
        end
    end
end

--------------------------------------------------------------------
-- 歌单
--------------------------------------------------------------------
local function build_playlist(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"歌单推荐","按场景挑选歌单","共 6 个精选歌单",true)

    R.pl_card = {}
    local CW,CH,GX,GY = 262,186,22,14
    for i=1,6 do
        local col,row = (i-1)%3, math.floor((i-1)/3)
        local x,y = 20+col*(CW+GX), 56+row*(CH+GY)
        -- 空 container 作组，卡底 shape 画（无子控件不画滚动条），内容收进组内
        local grp = airui.container({parent=p,x=x,y=y,w=CW,h=CH,color=C.bg,radius=0})
        theme.nilcall(grp,"set_color",C.bg,0)
        local card = theme.shape(grp,0,0,CW,CH)
        theme.put(card,{
            theme.rc(0,0,CW,CH,C.card,14),
            theme.rc(0,0,CW,CH,C.line,14),
            theme.rc(1,1,CW-2,CH-2,C.card,13),
        })
        theme.cover(grp,10,10,100,i+3,theme.first_char(mock.PLAYLISTS[i].n),12)
        T(grp,118,14,138,28,mock.PLAYLISTS[i].n,C.blue,17,AL)
        T(grp,118,48,138,62,mock.PLAYLISTS[i].d,C.sub,16,AL)
        T(grp,118,130,138,22,mock.PLAYLISTS[i].c.." 首歌曲 - 点击查看",C.cyan,16,AL)
        R.pl_card[i] = grp
        H(grp,0,0,CW,CH,function() S.plDetail=i; R.pl_off=0; refresh_page("playlist") end)
    end

    R.pl_detail = B(p,0,0,900,458,C.bg,0)
    -- 列表层先建（z 序在下），滚动时行只会钻到头部下面被遮住
    R.pl_list = B(R.pl_detail,0,142,900,316,C.bg,0)
    R.pl_songs = {}
    R.pl_off = 0
    for i=1,7 do
        local y = (i-1)*62
        -- 空 container 组 + shape 底：消除行底部滚动条横线
        local rowg = airui.container({parent=R.pl_list,x=16,y=y,w=868,h=58,color=C.bg,radius=0})
        theme.nilcall(rowg,"set_color",C.bg,0)
        local bgs = theme.shape(rowg,0,0,868,58)
        theme.put(bgs,{
            theme.rc(0,0,868,58,C.card,10),
            theme.rc(1,1,866,56,C.card,9),
        })
        -- 设计稿：彩色封面块 + 首字 + 音符（无序号竖条）
        local cov = theme.songcover(rowg,10,7,44,i,8)
        local mk = cov.mk
        local nm = T(rowg,64,6,620,26,"",C.text,18,AL)
        local ar = T(rowg,64,32,620,20,"",C.sub,16,AL)
        local ab = B(rowg,818,10,38,38,C.blue,8)
        I(ab,9,9,20,20,"plus",C.white,2)
        R.pl_songs[i] = {nm=nm,ar=ar,cov=cov,mk=mk,row=rowg,idx=nil,n=nil}
        H(rowg,818,10,38,38,function()
            local it = R.pl_songs[i].idx
            if it then M.add(it) end
        end)
    end
    -- 右侧只保留透明拖动区，不画轨道/滑块（按截图去掉蓝白竖条）
    R.pl_sync = false
    R.pl_scroll = theme.slider(R.pl_detail,876,142,22,300,0,function(_, v)
        if R.pl_sync then return end
        v = tonumber(v)
        if not v then return end
        local pl = mock.PLAYLISTS[S.plDetail+1]
        local total = math.max(1, tonumber(pl and pl.c) or 12)
        local maxoff = math.max(0, total*62-316)
        R.pl_off = math.floor((v*maxoff+50)/100)
        refresh_page("playlist")
    end)
    -- 头部遮罩最后建：永远压在列表之上，滑动时不会覆盖头部
    R.pl_head = B(R.pl_detail,0,0,900,142,C.bg,0)
    T(R.pl_head,16,0,200,28,"< 返回歌单列表",C.sub,16,AL)
    H(R.pl_head,16,0,200,28,function() S.plDetail=-1; refresh_page("playlist") end)
    R.pl_covmk = theme.cover(R.pl_head,16,28,96,3,"",12)
    R.pl_title = T(R.pl_head,126,30,420,34,"",C.blue,22,AL)
    R.pl_desc  = T(R.pl_head,126,70,520,24,"",C.sub,16,AL)
    R.pl_cnt   = T(R.pl_head,126,96,320,24,"",C.cyan,16,AL)
end
local function refresh_playlist()
    local detail = S.plDetail>=0
    for i=1,6 do call(R.pl_card[i],"set_hidden",detail) end
    call(R.pl_detail,"set_hidden",not detail)
    if not detail then return end
    local pl = mock.PLAYLISTS[S.plDetail+1]
    if not pl then return end
    call(R.pl_title,"set_text",pl.n)
    call(R.pl_desc,"set_text",pl.d)
    call(R.pl_cnt,"set_text","共 "..pl.c.." 首 - 精选推荐")
    if R.pl_covmk then pcall(R.pl_covmk.set_text,R.pl_covmk,theme.first_char(pl.n)) end
    -- 连续滚动：行池 7 行，按像素偏移重排，头不动、列表在下方滑动
    local total   = math.max(1, tonumber(pl.c) or 12)
    local VIEW    = 316
    local content = total*62
    local maxoff  = math.max(0, content-VIEW)
    local off     = math.max(0, math.min(maxoff, R.pl_off or 0))
    R.pl_off = off
    local first = math.floor(off/62)
    local dy    = off - first*62
    for i=1,7 do
        local it = R.pl_songs[i]
        local n = first+i
        if n <= total then
            local idx = (S.plDetail*4+(n-1)) % #mock.SONGS
            local s = mock.song(idx)
            it.idx = idx
            call(it.row,"set_pos",16,(i-1)*62-dy)
            call(it.row,"set_hidden",false)
            if it.n ~= idx then
                it.n = idx
                call(it.nm,"set_text",s.n)
                call(it.ar,"set_text",s.a)
                theme.songcover_set(it.cov, idx, s.n)
            end
        else
            it.idx = nil
            call(it.row,"set_hidden",true)
        end
    end
    -- 滑块隐藏但仍与内容偏移保持同步（无可见滚动条）
    if R.pl_scroll then
        R.pl_sync = true
        call(R.pl_scroll,"set_value",maxoff>0 and math.floor((off*200+maxoff)/(2*maxoff)) or 0,false)
        R.pl_sync = false
    end
end

--------------------------------------------------------------------
-- 正在播放
--------------------------------------------------------------------
local function func_btn(parent,x,y,i,h)
    local f = FUNC[i]
    local card = BB(parent,x,y,205,h,C.card,11,C.line,1)
    -- 图标底改成 shape 竖向渐变（上亮下深），和快捷功能浮层保持同一套观感
    local ib = theme.shape(card,3,3,42,42)
    local sh = theme.shape(card,9,9,30,30)
    R.func_ic[i],R.func_ib[i] = sh,ib
    R.func_lb[i] = T(card,54,11,142,26,f[2],C.text,15,AL)
    H(parent,x,y,205,h,function() M.func(f[1]) end)
end

local function build_playing(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"正在播放","大功率高清音效","专业 KTV 控制台",true)

    local top = B(p,16,52,868,158,C.bg,0)
    local cov = theme.songcover(top,0,0,156,1,14)
    R.play_cov, R.play_mark = cov, cov.mk
    R.play_title = T(top,172,4,560,34,"",C.blue,22,AL)
    R.play_artist = T(top,172,38,560,24,"",C.sub,16,AL)
    B(top,172,72,680,8,C.track,4)
    R.play_fill = theme.shape(top,172,72,680,8)
    R.play_knob = theme.circle(top,172,68,14,C.knob)
    R.play_time = T(top,172,84,680,22,"",C.sub,16,AL)
    R.play_seek = slider(top,172,64,680,"seek",S.progress)

    I(top,430,120,22,22,"vol",C.cyan,2)
    B(top,462,126,240,8,C.track,4)
    R.vol_fill = theme.shape(top,462,126,240,8)
    R.vol_knob = theme.circle(top,462,122,14,C.knob)
    R.vol_pct = T(top,712,116,100,26,"",C.sub,16,AL)
    R.vol_seek = slider(top,462,118,240,"volume",S.volume)

    R.func_ic,R.func_ib,R.func_lb = {},{},{}
    for i=1,4 do func_btn(p,16+(i-1)*218,218,i,48) end
    for i=5,8 do func_btn(p,16+(i-5)*218,272,i,48) end

    local q = BB(p,16,330,868,116,C.card,12,C.line,1)
    T(q,14,6,400,24,"播放队列 - 即将演唱",C.text,16,AL)
    R.q_num = T(q,20,36,34,34,"",C.cyan,20,AC)
    local qcov = theme.songcover(q,62,32,56,1,8)
    R.q_cov, R.q_mark = qcov, qcov.mk
    R.q_title = T(q,130,36,560,26,"",C.text,20,AL)
    R.q_artist = T(q,130,66,560,22,"",C.sub,16,AL)
    R.q_status = T(q,760,48,90,28,"待唱",C.cyan,16,AC)
end
local function refresh_playing()
    local s = mock.song(S.playIndex)
    if not s then return end
    local total = mock.durSec(s.d)
    call(R.play_title,"set_text",s.n)
    call(R.play_artist,"set_text","演唱："..s.a.."  -  "..s.d)
    theme.songcover_set(R.play_cov, S.playIndex, s.n)
    local pw = math.floor(680*S.progress/100)
    grad_progress(R.play_fill,680,S.progress,8,true)
    call(R.play_knob,"set_pos",172+pw-7,68)
    call(R.play_time,"set_text",mock.fmt(S.play_sec).." / "..s.d)
    local vw = math.floor(240*S.volume/100)
    grad_progress(R.vol_fill,240,S.volume,8,true)
    call(R.vol_knob,"set_pos",462+vw-7,122)
    call(R.vol_pct,"set_text",S.volume.."%")

    for i=1,8 do
        local f = FUNC[i]
        local on = (f[1]=="toggle" and S.playing) or (f[1]=="mute" and S.mute) or
                   (f[1]=="origin" and S.origin) or (f[1]=="atmos" and S.atmos) or
                   (f[1]=="eq" and S.eqOpen) or (f[1]=="control" and S.acOpen)
        local icon = f[1]=="toggle" and (S.playing and "pause" or "play") or f[3]
        theme.icon_set(R.func_ic[i],30,30,icon,C.white,2)
        -- 图标底：未激活用各自彩色渐变，激活换成橙色渐变
        local g = mock.FUNC_GRADS[i]
        local g1,g2 = (on and 0xFFD27A or g[1]), (on and C.orange2 or g[2])
        theme.put(R.func_ib[i],{
            theme.rc(0,0,42,42,g2,12),
            theme.rc(0,0,42,30,theme.mix(g1,g2,40/100),12),
            theme.rc(0,0,42,16,g1,12),
        })
        local nm = f[1]=="origin" and (S.origin and "原唱" or "伴唱") or f[2]
        call(R.func_lb[i],"set_text",nm)
    end

    local nxt,o = mock.nextOrder(1)
    if o then
        local q = mock.song(o.i)
        call(R.q_num,"set_text",tostring(nxt))
        call(R.q_title,"set_text",q.n)
        call(R.q_artist,"set_text",q.a)
        call(R.q_status,"set_text","待唱")
        theme.songcover_set(R.q_cov, o.i, q.n)
    else
        call(R.q_title,"set_text","暂无待唱歌曲")
        call(R.q_artist,"set_text","")
        call(R.q_status,"set_text","")
    end
end

--------------------------------------------------------------------
-- 系统设置
--------------------------------------------------------------------
-- 实心月牙（对齐设计稿）：白色圆盘 + 底色圆盘错位相减
-- 22px 下画弧线会糊成一圈疙瘩，用两圆相减边缘最干净
local function moon_items(out, cut)
    return { theme.cl(9,11,8,out), theme.cl(14,9,7,cut) }
end
local function build_settings(s)
    local p = B(s,0,0,900,458,C.bg,0)
    head(p,"系统设置","参数调节与设备信息",nil,true)

    local c1 = BB(p,16,54,426,194,C.card,14,C.line,1)
    I(c1,16,14,20,20,"vol",C.cyan,2)
    T(c1,44,10,360,28,"音量与亮度",C.text,16,AL)
    T(c1,16,48,200,24,"系统音量",C.sub,16,AL)
    R.set_vol_lb = T(c1,260,48,150,24,"",C.cyan,16,AR)
    B(c1,16,78,394,10,C.track,5)
    R.set_vol_fill = theme.shape(c1,16,78,394,10)
    R.set_vol_sl = slider(c1,16,72,394,"setVol",S.volume)
    T(c1,16,108,200,24,"屏幕亮度",C.sub,16,AL)
    R.set_bri_lb = T(c1,260,108,150,24,"",C.cyan,16,AR)
    B(c1,16,138,394,10,C.track,5)
    R.set_bri_fill = theme.shape(c1,16,138,394,10)
    R.set_bri_sl = slider(c1,16,132,394,"setBri",S.brightness)

    local c2 = BB(p,454,54,430,194,C.card,14,C.line,1)
    I(c2,16,14,20,20,"star",C.cyan,2)
    T(c2,44,10,360,28,"主题风格",C.text,16,AL)
    T(c2,16,52,60,26,"配色",C.sub,16,AL)
    local keys = {"blue","purple","cyan"}
    local names = {"科技蓝","梦幻紫","清新青"}
    R.theme_sw = {}
    for i=1,3 do
        local x = 84+(i-1)*112
        local b = B(c2,x,50,106,32,C.card2,10)
        R.theme_sw[i] = theme.switch(b,6,4,S.theme==keys[i],40)
        T(b,50,3,54,26,names[i],C.text,16,AL)
        H(b,0,0,106,32,function() M.set_theme(keys[i]) end)
    end
    T(c2,16,104,60,26,"模式",C.sub,16,AL)
    local d = S.mode=="dark"
    -- 按钮底用 shape，子控件直接挂 c2：避免 container 溢出画滑块线
    local bx1,bx2 = 84,246
    local bg1 = theme.shape(c2,bx1,100,148,36)
    local bg2 = theme.shape(c2,bx2,100,148,36)
    local sw1 = theme.switch(c2,bx1+6,106,d,40)
    local sw2 = theme.switch(c2,bx2+6,106,not d,40)
    local icm = theme.shape(c2,bx1+52,106,22,22)
    local ics = theme.shape(c2,bx2+52,106,22,22)
    theme.put(icm, moon_items(d and C.white or C.sub, d and C.acw or C.card2))
    theme.icon_set(ics,22,22,"sun",(not d) and C.white or C.sub,2)
    T(c2,bx1+78,102,64,30,"深色",C.text,17,AL)
    T(c2,bx2+78,102,64,30,"浅色",C.text,17,AL)
    R.mode_sw = {sw1,sw2,bg1,bg2,icm,ics}
    H(c2,bx1,100,148,36,function() M.set_mode("dark") end)
    H(c2,bx2,100,148,36,function() M.set_mode("light") end)

    local c3 = BB(p,16,260,426,186,C.card,14,C.line,1)
    I(c3,16,12,20,20,"info",C.cyan,2)
    T(c3,44,8,360,28,"系统信息",C.text,16,AL)
    local info = {
        {"设备型号","Air8603 串口屏"},{"屏幕分辨率","1024 × 600"},
        {"系统版本","AirUI KTV V2.6.0"},{"曲库版本","2026.11 高清曲库"},
        {"音频输出","HDMI / 光纤 / 模拟"},{"网络连接","已连接 - 有线"},
    }
    for i=1,#info do
        local y = 42+(i-1)*24
        T(c3,16,y,180,22,info[i][1],C.sub,16,AL)
        T(c3,196,y,214,22,info[i][2],C.text,16,AR)
    end

    local c4 = BB(p,454,260,430,186,C.card,14,C.line,1)
    I(c4,16,12,20,20,"check",C.cyan,2)
    T(c4,44,8,360,28,"快捷操作",C.text,16,AL)
    local btns = {{"查看已点歌曲","ordered"},{"进入排行榜","rank"},{"恢复默认设置","reset"}}
    for i=1,3 do
        local y = 50+(i-1)*44
        local b = B(c4,16,y,398,38,i==1 and C.blue or C.func,9)
        T(b,0,4,398,30,btns[i][1],i==1 and C.white or C.sub,16,AC)
        H(c4,16,y,398,38,function()
            if btns[i][2]=="reset" then
                mock.reset(); theme.apply(S.mode,S.theme); C=theme.C
                theme.defer(function() theme.recolor(); refresh_all() end)
                M.toast("已恢复默认设置")
            else M.go(btns[i][2]) end
        end)
    end
end
local function refresh_settings()
    call(R.set_vol_lb,"set_text",S.volume.."%")
    call(R.set_bri_lb,"set_text",S.brightness.."%")
    grad_progress(R.set_vol_fill,394,S.volume,10)
    grad_progress(R.set_bri_fill,394,S.brightness,10)
    local keys = {"blue","purple","cyan"}
    for i=1,3 do theme.sw_set(R.theme_sw[i],S.theme==keys[i],C.blue) end
    theme.sw_set(R.mode_sw[1],S.mode=="dark",C.blue)
    theme.sw_set(R.mode_sw[2],S.mode=="light",C.cyan)
    -- 选中态：深蓝胶囊 + 1px 淡蓝灰细描边（对齐设计稿，不再是粗白框）
    -- 未选中：card2 实底、无边框
    local line_on = theme.mix(C.white,C.bg,55/100)
    theme.put(R.mode_sw[3],{
        theme.rc(0,0,148,36,S.mode=="dark" and line_on or C.card2,10),
        theme.rc(1,1,146,34,S.mode=="dark" and C.acw or C.card2,9),
    })
    theme.put(R.mode_sw[4],{
        theme.rc(0,0,148,36,S.mode=="light" and line_on or C.card2,10),
        theme.rc(1,1,146,34,S.mode=="light" and C.acw or C.card2,9),
    })
    theme.put(R.mode_sw[5], moon_items(S.mode=="dark" and C.white or C.sub,
        S.mode=="dark" and C.acw or C.card2))
    theme.icon_set(R.mode_sw[6],22,22,"sun",S.mode=="light" and C.white or C.sub,2)
end

--------------------------------------------------------------------
-- 迷你条 / 快捷功能浮层
--------------------------------------------------------------------
-- 功能卡：统一按设计稿（图标在左、文字在右的水平条），深浅两套只是底色不同
-- 深/浅两套浮层各建一次，只切显隐，不再重建（重建会把 z 序顶到弹窗之上）
local POP_CW, POP_CH, POP_GX, POP_GY = 196, 78, 12, 14
local function pop_btn(set,i,row)
    local f = FUNC[i]
    local g = mock.FUNC_GRADS[i]
    local x = 20+(i-1-(row-1)*4)*(POP_CW+POP_GX)
    local y = 60+(row-1)*(POP_CH+POP_GY)
    local pop = set.pop
    -- 卡底用 shape，可整体换色表示激活；不用 container 避免滚动条横线
    local back = theme.shape(pop,x,y,POP_CW,POP_CH)
    -- 图标底：上亮下深三层叠加近似竖向渐变（对齐设计稿的彩色方块）
    local ib = theme.shape(pop,x+12,y+18,42,42)
    theme.put(ib,{
        theme.rc(0,0,42,42,g[2],12),
        theme.rc(0,0,42,30,theme.mix(g[1],g[2],40/100),12),
        theme.rc(0,0,42,16,g[1],12),
    })
    local sh = theme.shape(pop,x+18,y+24,30,30)
    set.ic[i], set.ib[i], set.bg[i] = sh, ib, back
    set.lb[i] = T(pop,x+62,y+22,126,32,f[2],C.text,17,AL)
    H(pop,x,y,POP_CW,POP_CH,function() M.func(f[1]) end)
end

local function build_mini(root)
    local p = B(root,0,516,1024,84,C.mini,0)
    R.mini_panel = p
    local mcov = theme.songcover(p,12,10,64,1,10)
    R.mini_cov, R.mini_mark = mcov, mcov.mk
    R.mini_name = T(p,88,10,170,28,"",C.blue,20,AL)
    R.mini_artist = T(p,88,40,170,24,"",C.sub,18,AL)
    local prev = theme.circle(p,270,16,52,C.orange)
    I(prev,13,13,26,26,"prev",C.black,2)
    H(p,270,16,52,52,function() M.change(-1) end)
    local play = theme.circle(p,336,13,58,C.blue)
    R.mini_icon = theme.shape(play,15,15,28,28)
    H(p,336,13,58,58,function() M.toggle_play() end)
    local next = theme.circle(p,408,16,52,C.orange)
    I(next,13,13,26,26,"next",C.black,2)
    H(p,408,16,52,52,function() M.change(1) end)
    B(p,478,37,238,10,C.track,5)
    R.mini_fill = theme.shape(p,478,37,238,10)
    R.mini_seek = slider(p,478,31,238,"seek",S.progress)
    R.mini_time = T(p,716,28,120,28,"",C.sub,16,AC)
    -- 图 1/图 2：功能按钮（浅色淡蓝紫 / 深色深蓝、青色图标）+ 已点胶囊，两者留 6px 间隙不重叠
    local fb = B(p,830,24,96,38,C.acw,10)
    I(fb,10,9,20,20,"set",C.cyan,2); T(fb,34,5,54,28,"功能",C.text,16,AL)
    H(p,830,24,96,38,function() M.toggle_funcpop() end)
    local cb = B(p,932,24,86,38,C.card,10)
    -- "已点 N 首" 合成一个 label，避免两段文字互相挤压、被裁成"已 9 首"
    R.mini_count = T(cb,4,5,78,28,"",C.sub,15,AC)
    H(p,932,24,86,38,function() M.go("ordered") end)

end

-- 前向声明：面板级隐藏（快捷功能浮层与弹窗互斥用）
local hide_modal_panels

-- 浮层必须在页面容器之后创建，否则 z 序被页面盖住（"功能点不动"）
-- 深/浅两套浮层一次性建好（都挂在 root 且早于弹窗），z 序恒定：
-- 页面 < 遮罩/快捷功能 < 调音·空调弹窗 < toast，按哪个都在最上面
local function build_funcpop(root)
    -- 弹窗已存在才建浮层 → 浮层 z 序会跑到弹窗上面，记下来，开弹窗时先收掉它
    R.fup_late = (R.modal_mask ~= nil) or nil
    -- 半透明遮罩：弹窗弹出时其他内容整体压暗，点遮罩即关闭
    R.func_mask = theme.box_a(root,0,0,1024,600,0x040814,0,150)
    H(R.func_mask,0,0,1024,600,function() M.toggle_funcpop() end)
    call(R.func_mask,"set_hidden",true)
    R.fup = {}
    local modes = {"dark","light"}
    for k=1,#modes do
        local set = {mode=modes[k],ic={},ib={},lb={},bg={}}
        -- 居中弹窗：860x256 正好在屏幕中心，不用整宽面板（整宽 1024 会撑出横向滚动条）
        set.pop = B(root,82,172,860,256,C.toast_bg,18)
        T(set.pop,20,12,300,32,"快捷功能",C.text,20,AL)
        T(set.pop,796,10,40,30,"X",C.sub,22,AC)
        H(set.pop,788,6,54,40,function() M.toggle_funcpop() end)
        for i=1,4 do pop_btn(set,i,1) end
        for i=5,8 do pop_btn(set,i,2) end
        call(set.pop,"set_hidden",true)
        R.fup[modes[k]] = set
    end
end
-- 收起快捷功能浮层（两套都收）
function M.hide_funcpop()
    S.funcPop = false
    for _,set in pairs(R.fup or {}) do call(set.pop,"set_hidden",true) end
    call(R.func_mask,"set_hidden",true)
end
function M.toggle_funcpop()
    if not (R.fup and R.fup.dark) then
        if build_funcpop then pcall(build_funcpop, airui.screen) end
        if not (R.fup and R.fup.dark) then return end
    end
    S.funcPop = not S.funcPop
    -- 只显示与当前主题匹配的那一套，避免两套叠在一起
    for m,set in pairs(R.fup) do
        call(set.pop,"set_hidden", not (S.funcPop and m == S.mode))
    end
    if R.func_mask then call(R.func_mask,"set_hidden",not S.funcPop) end
    if S.funcPop then refresh_page("funcpop") end
end
local function refresh_mini()
    local s = mock.song(S.playIndex)
    if not s then return end
    theme.songcover_set(R.mini_cov, S.playIndex, s.n)
    call(R.mini_name,"set_text",s.n)
    call(R.mini_artist,"set_text",s.a)
    call(R.mini_count,"set_text","已点 "..#S.ordered.." 首")
    grad_progress(R.mini_fill,238,S.progress,10)
    call(R.mini_time,"set_text",mock.fmt(S.play_sec).." / "..s.d)
    theme.icon_set(R.mini_icon,28,28,S.playing and "pause" or "play",C.black,2)
end
local function refresh_funcpop()
    -- 两套浮层都刷新，切主题时另一套也已是最新状态
    for _,set in pairs(R.fup or {}) do
        local light = (set.mode == "light")
        local base = light and C.card or C.card2
        for i=1,8 do
            local f = FUNC[i]
            local on = (f[1]=="toggle" and S.playing) or (f[1]=="mute" and S.mute) or
                       (f[1]=="origin" and S.origin) or (f[1]=="atmos" and S.atmos) or
                       (f[1]=="eq" and S.eqOpen) or (f[1]=="control" and S.acOpen)
            local icon = f[1]=="toggle" and (S.playing and "pause" or "play") or f[3]
            theme.icon_set(set.ic[i],30,30,icon,C.white,2)
            -- 整卡：未激活=细边深卡；激活=橙色描边 + 棕色渐变底（图标底保持各自彩色，不跟着变橙）
            if on then
                theme.put(set.bg[i],{
                    theme.rc(0,0,POP_CW,POP_CH,C.orange,14),
                    theme.rc(2,2,POP_CW-4,POP_CH-4,light and 0x6B3A16 or 0x5C3113,12),
                    theme.rc(2,2,POP_CW-4,math.floor((POP_CH-4)*45/100),0x6B3A16,12),
                })
            else
                theme.put(set.bg[i],{
                    theme.rc(0,0,POP_CW,POP_CH,C.line,14),
                    theme.rc(1,1,POP_CW-2,POP_CH-2,base,13),
                })
            end
            local nm = f[1]=="origin" and (S.origin and "原唱" or "伴唱") or f[2]
            call(set.lb[i],"set_text",nm)
        end
    end
end

--------------------------------------------------------------------
-- 弹窗：调音 / 空调
--------------------------------------------------------------------
local function build_modal(root)
    R.modal_mask = theme.box_a(root,0,0,1024,600,0x040814,0,153)
    H(R.modal_mask,0,0,1024,600,function() M.close_modal() end)

    -- 音效 / 空调 两个独立面板：靠面板级 set_hidden 切换，杜绝内容串台
    R.eq_panel = B(root,252,80,520,440,C.toast_bg,18)
    R.ac_panel = B(root,252,80,520,440,C.toast_bg,18)
    local function panel_head(panel, title)
        T(panel,20,12,400,32,title,C.blue,19,AL)
        T(panel,476,12,32,32,"X",C.sub,20,AC)
        H(panel,468,8,46,40,function() M.close_modal() end)
    end
    panel_head(R.eq_panel,"音效调音")
    panel_head(R.ac_panel,"空调控制")

    local EP = R.eq_panel   -- 音效内容全部挂 EP
    R.eq = {val={},fill={},rows={}}
    local labels = {"音调","麦克风音量","系统音量"}
    local acts = {"pitch","micVol","setVol"}
    local vals = {S.pitch,S.micVol,S.volume}
    for i=1,3 do
        local y = 52+(i-1)*108
        local row = BB(EP,16,y,488,100,C.card,12,C.line,1)
        R.eq.rows[i] = row
        T(row,16,10,220,26,labels[i],C.text,17,AL)
        R.eq.val[i] = T(row,284,10,188,26,"",C.cyan,18,AR)
        B(row,16,42,456,14,C.track,7)
        R.eq.fill[i] = theme.shape(row,16,42,456,14)
        slider(row,16,36,456,acts[i],vals[i])
        if i==1 then
            T(row,16,64,150,22,"低",C.sub,15,AL)
            T(row,164,64,180,22,"标准",C.sub,15,AC)
            T(row,364,64,108,22,"高",C.sub,15,AR)
        else
            T(row,16,64,150,22,"小",C.sub,15,AL)
            T(row,364,64,108,22,"大",C.sub,15,AR)
        end
    end

    local AP = R.ac_panel   -- 空调内容全部挂 AP
    R.ac = {}
    local ac = R.ac
    local pw = BB(AP,16,56,488,58,C.card,12,C.line,1)
    ac.power = pw
    T(pw,14,6,200,24,"空调电源",C.text,16,AL)
    ac.sw = theme.switch(pw,376,6,S.acOn,88)
    H(pw,372,4,96,34,function()
        S.acOn = not S.acOn
        M.toast(S.acOn and "空调已开启" or "空调已关闭")
        refresh_page("ac")
    end)
    ac.state = T(pw,14,30,380,24,"",C.sub,16,AL)

    local function cardsel(y,tag)
        local row = BB(AP,16,y,488,98,C.card,12,C.line,1)
        ac[tag.."row"] = row
        ac[tag.."lbl"] = T(row,14,4,300,24,"",C.cyan,16,AL)
        local al = B(row,14,32,52,52,C.blue,26)
        I(al,13,13,26,26,"back",C.white,2)
        local card = B(row,76,28,336,60,C.acw,12)
        ac[tag.."ic"] = theme.shape(card,14,16,28,28)
        ac[tag.."name"] = T(card,52,8,270,28,"",C.text,20,AL)
        ac[tag.."desc"] = T(card,52,34,270,22,"",C.sub,16,AL)
        local ar = B(row,422,32,52,52,C.blue,26)
        local ar_ic = theme.shape(ar,13,13,26,26)
        theme.put(ar_ic,{
            theme.ln(2,2,15,13,C.white,3),
            theme.ln(15,13,2,24,C.white,3),
        })
        ac[tag.."dots"] = {}
        for i=1,4 do
            ac[tag.."dots"][i] = theme.circle(row,190+(i-1)*28,82,8,i==1 and C.blue or C.card2)
            H(row,182+(i-1)*28,78,24,18,function() M.ac_set(tag,i) end)
        end
        H(row,14,32,52,52,function() M.ac_step(tag,-1) end)
        H(row,422,32,52,52,function() M.ac_step(tag,1) end)
        H(card,0,0,336,60,function() M.ac_step(tag,1) end)
    end
    cardsel(120,"mode")
    cardsel(224,"fan")

    local tr = BB(AP,16,328,488,100,C.card,12,C.line,1)
    ac.temp_row = tr
    T(tr,14,6,200,24,"温度设置",C.text,16,AL)
    ac.temp_lbl = T(tr,320,6,154,24,"",C.cyan,16,AR)
    local dn = theme.circle(tr,118,38,56,C.blue)
    T(dn,0,12,56,34,"-",C.white,30,AC)
    ac.temp_big = T(tr,184,34,120,64,"",C.text,46,AC)
    local up = theme.circle(tr,314,38,56,C.blue)
    T(up,0,12,56,34,"+",C.white,30,AC)
    H(tr,118,38,56,56,function() M.ac_temp(-1) end)
    H(tr,314,38,56,56,function() M.ac_temp(1) end)

    call(R.modal_mask,"set_hidden",true)
    call(R.eq_panel,"set_hidden",true)
    call(R.ac_panel,"set_hidden",true)
end

-- 弹窗切换：两个独立面板，只切面板整体显隐（面板级 set_hidden 可靠）
function M.open_modal(kind)
    local eq = (kind=="eq")
    -- 弹窗 z 序固定在快捷功能浮层之上（浮层只切显隐、从不重建），点哪个都显示在最上层
    -- 只有浮层晚于弹窗建成（启动瞬间抢点）时才会反压，这时先把浮层收掉
    if R.fup_late then M.hide_funcpop() end
    call(R.modal_mask,"set_hidden",false)
    call(R.eq_panel,"set_hidden",not eq)
    call(R.ac_panel,"set_hidden",eq)
    refresh_page(eq and "eq" or "ac")
end
function M.close_modal()
    if hide_modal_panels then hide_modal_panels() end
    S.eqOpen,S.acOpen = false,false
    refresh_page("playing"); refresh_page("funcpop")
end
-- 面板级隐藏（不改开合状态，供浮层互斥时调用）
hide_modal_panels = function()
    call(R.modal_mask,"set_hidden",true)
    call(R.eq_panel,"set_hidden",true)
    call(R.ac_panel,"set_hidden",true)
end
function M.ac_step(tag,step)
    local arr = tag=="mode" and mock.AC_MODES or mock.AC_FANS
    local cur = (tag=="mode") and S.acMode or S.acFan
    local idx = 1
    for i=1,#arr do if arr[i].key==cur then idx=i end end
    idx = ((idx-1+step) % #arr)+1
    if tag=="mode" then S.acMode=arr[idx].key else S.acFan=arr[idx].key end
    M.toast((tag=="mode" and "模式：" or "风速：")..arr[idx].name)
    refresh_page("ac")
end
function M.ac_set(tag,idx)
    local arr = tag=="mode" and mock.AC_MODES or mock.AC_FANS
    if not arr[idx] then return end
    if tag=="mode" then S.acMode=arr[idx].key else S.acFan=arr[idx].key end
    M.toast((tag=="mode" and "模式：" or "风速：")..arr[idx].name)
    refresh_page("ac")
end
function M.ac_temp(step)
    if not S.acOn then M.toast("请先开启空调") return end
    S.acTemp = math.max(16, math.min(30, S.acTemp+step))
    M.toast("空调温度："..S.acTemp.."°C")
    refresh_page("ac")
end

-- 渐变填充：左蓝右青，多段 rect 近似 CSS linear-gradient
grad_bar = function(sh, w, pct, h)
    if not sh then return end
    if pct<=0 then theme.put(sh,{}) return end
    local total = math.floor(w*pct/100)
    local seg, items = 18, {}
    for i=0,seg-1 do
        local x1 = math.floor(total*i/seg)
        local x2 = math.floor(total*(i+1)/seg)
        if x2>x1 then
            local col = theme.mix(C.blue,C.cyan,i/(seg-1))
            items[#items+1] = theme.rc(x1,0,x2-x1,h,col,0)
        end
    end
    theme.put(sh,items)
end
-- 迷你条进度：左圆头青 → 右黄渐变 + 末端光点（对齐设计稿）
grad_progress = function(sh, w, pct, h, nodot)
    if not sh then return end
    if pct<=0 then theme.put(sh,{}) return end
    local total = math.max(h, math.floor(w*pct/100))
    local r = math.floor(h/2)
    local seg, items = 14, {}
    items[#items+1] = theme.cl(r, r, r, C.cyan)
    for i=0,seg-1 do
        local x1 = math.floor((total-2*r)*i/seg)+r
        local x2 = math.floor((total-2*r)*(i+1)/seg)+r
        if x2>x1 then
            items[#items+1] = theme.rc(x1,0,x2-x1,h,theme.mix(C.cyan,0xFFC24A,i/(seg-1)),0)
        end
    end
    -- 已有独立圆点滑块（正在播放页）时不重复画光点
    if not nodot then items[#items+1] = theme.cl(total-r, r, r, 0xFFD24D) end
    theme.put(sh,items)
end
local function refresh_eq()
    local vals = {S.pitch,S.micVol,S.volume}
    local suf = {"","%","%"}
    for i=1,3 do
        call(R.eq.val[i],"set_text",vals[i]..suf[i])
        grad_bar(R.eq.fill[i],456,vals[i],14)
    end
end
local function refresh_ac()
    local ac = R.ac
    theme.sw_set(ac.sw,S.acOn,C.blue)
    call(ac.state,"set_text",mock.acStatus())
    call(ac.temp_lbl,"set_text",S.acTemp.."°C")
    call(ac.temp_big,"set_text",S.acTemp.."°")
    call(ac.temp_row,"set_color",S.acOn and C.card or C.track,255)
    local function draw(tag,arr,cur)
        local idx = 1
        for i=1,#arr do if arr[i].key==cur then idx=i end end
        local it = arr[idx]
        call(ac[tag.."lbl"],"set_text",it.name)
        call(ac[tag.."name"],"set_text",it.name)
        call(ac[tag.."desc"],"set_text",it.desc or "")
        theme.icon_set(ac[tag.."ic"],28,28,it.sym or "wind",C.cyan,2)
        for i=1,4 do
            call(ac[tag.."dots"][i],"set_color",i==idx and C.blue or C.card2,255)
        end
        call(ac[tag.."row"],"set_color",S.acOn and C.card or C.track,255)
    end
    draw("mode",mock.AC_MODES,S.acMode)
    draw("fan",mock.AC_FANS,S.acFan)
end

--------------------------------------------------------------------
-- toast
--------------------------------------------------------------------
local function build_toast(root)
    -- 正中间显示，放大一倍 800×128；空 container 底 + label 挂 root，避免溢出滚动条
    local tx,ty,tw,th = 112,236,800,128
    -- 全屏遮罩：提示弹出时背景压暗，点击任意处立即消失
    R.toast_mask = theme.box_a(root,0,0,1024,600,0x040814,0,120)
    H(R.toast_mask,0,0,1024,600,function() M.hide_toast() end)
    call(R.toast_mask,"set_hidden",true)
    R.toast_bg = B(root,tx,ty,tw,th,C.toast_bg,64)
    R.toast_lb = T(root,tx,ty,tw,th,"",C.text,40,AC)
    -- 点击任意位置消失
    R.toast_hit = H(root,tx,ty,tw,th,function() M.hide_toast() end)
    call(R.toast_bg,"set_hidden",true)
    call(R.toast_hit,"set_hidden",true)
    call(R.toast_lb,"set_text","")
end

--------------------------------------------------------------------
-- 总装
--------------------------------------------------------------------
function M.build(root)
    C = theme.C
    M_gen = M_gen + 1
    theme.clear_registry()
    theme.reset_draw()
    R = {scr={},refresh={},built={}}

    -- 阶段 1：先建框架 + 首页，让首帧尽快上屏（其余页在 task 里分帧补建）
    build_top(root)
    build_nav(root)
    build_mini(root)

    local names = {"home","category","artist","search","ordered","rank","playlist","playing","settings"}
    local builders = {build_home,build_category,build_artist,build_search,build_ordered,
                      build_rank,build_playlist,build_playing,build_settings}
    R.builders, R.names = builders, names
    for i=1,9 do
        R.scr[names[i]] = airui.container({parent=root,x=124,y=58,w=900,h=458,color=C.bg,radius=0})
    end

    R.refresh.home     = refresh_home
    R.refresh.category = refresh_category
    R.refresh.artist   = refresh_artist
    R.refresh.search   = refresh_search
    R.refresh.ordered  = refresh_ordered
    R.refresh.rank     = refresh_rank
    R.refresh.playlist = refresh_playlist
    R.refresh.playing  = refresh_playing
    R.refresh.settings = refresh_settings
    R.refresh.mini     = refresh_mini
    R.refresh.funcpop  = refresh_funcpop
    R.refresh.eq       = refresh_eq
    R.refresh.ac       = refresh_ac

    -- 每步独立 pcall：任一步出错都不阻断后续框架（避免整屏空白 + 时钟不走）
    local function safe(label, fn)
        local ok,e = pcall(fn)
        if not ok then
            pcall(log.error,"ktv","build "..label..": "..tostring(e))
            -- 屏幕左上角显示错误，便于定位（正式版可删）
            pcall(function()
                T(root,130,60,860,28,"BUILD ERR "..label..": "..tostring(e),0xFF0000,16,AL)
            end)
        end
        return ok
    end
    safe("home", function() builders[1](R.scr.home) end)
    R.built[1] = true
    safe("refresh_home", function() refresh_page("home") end)

    local gen = M_gen
    safe("go", function() M.go("home") end)
    safe("clock", refresh_clock)

    -- 阶段 2：后台分帧补建其余 8 页 + 弹窗，每帧只建一页，避免长帧白屏
    sys.taskInit(function()
        sys.wait(30)
        local order = {2,3,4,5,6,7,8,9}
        for i=1,#order do
            if M_gen~=gen then return end
            local k = order[i]
            if not R.built[k] then
                local ok,e = pcall(builders[k], R.scr[names[k]])
                if not ok then
                    pcall(log.error,"ktv","build page "..names[k]..": "..tostring(e))
                    pcall(function()
                        T(root,130,60,860,28,"PAGE ERR "..names[k]..": "..tostring(e),0xFF0000,16,AL)
                    end)
                end
                R.built[k] = true
                refresh_page(names[k])
            end
            sys.wait(20)
        end
        if M_gen~=gen then return end
        local ok,e = pcall(build_funcpop, root)
        if not ok then pcall(log.error,"ktv","build funcpop: "..tostring(e)) end
        sys.wait(20)
        if M_gen~=gen then return end
        ok, e = pcall(build_modal, root)
        if not ok then pcall(log.error,"ktv","build modal: "..tostring(e)) end
        sys.wait(20)
        if M_gen~=gen then return end
        ok, e = pcall(build_toast, root)
        if not ok then pcall(log.error,"ktv","build toast: "..tostring(e)) end
        -- 原设计稿可能停在任意页，补建完成后跳过去
        if S.page ~= "home" then M.go(S.page) end
        R.ready = true
    end)

    sys.taskInit(function()
        local tick = 0
        while M_gen==gen do
            sys.wait(100)
            if M_gen~=gen then break end
            local ok,err = pcall(function()
                tick = tick+1
                M_clock = M_clock+1
                if tick%10==0 then refresh_clock() end
                if S.playing and tick%10==0 then
                    local total = mock.durSec(mock.song(S.playIndex).d)
                    S.play_sec = (S.play_sec+1) % (total+1)
                    S.progress = math.floor(S.play_sec*100/total)
                    refresh_page("playing"); refresh_page("mini")
                end
                if R.toast_until and M_clock>R.toast_until then
                    M.hide_toast()
                end
            end)
            if not ok then pcall(log.error,"ktv","tick error: "..tostring(err)) end
        end
    end)
end

function M.open()
    local ok,err = pcall(M.build, airui.screen)
    if not ok then pcall(log.error,"ktv","build failed: "..tostring(err)) end
end

function M.close()
    M_gen = M_gen+1
end

return M
