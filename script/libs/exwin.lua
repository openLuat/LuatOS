--[[
@module  exwin
@summary UI窗口管理扩展库
@version 2.2.0
@date    2026.10.22
@author  江访
@usage
本文件为窗口管理扩展库，核心业务逻辑为：
1、基于栈的窗口管理，栈顶为当前活动窗口
2、支持窗口生命周期回调（创建、销毁、获得焦点、失去焦点）
3、提供页面打开、关闭、查询活动、返回首页等导航功能
4、【v2.0】窗口可携带 owner（归属者）字段，形成「一级菜单 → 二级菜单 → 多级子页」的树形归属，
    从而支持「切换一级菜单时销毁其整棵子树」，避免窗口无上界堆积。
5、【v2.2】窗口可登记页面根控件（root），被盖住的页面自动隐藏根控件、回到它时再显示，
    避免下层页面在整屏重画时被重复绘制。未登记 root 的窗口行为不变。

窗口定义通过 Lua 表描述，需包含以下回调：
- on_create()：窗口创建时调用(必须有)
- on_destroy()：窗口销毁时调用(必须有)
- on_get_focus()：窗口获得焦点时调用
- on_lose_focus()：窗口失去焦点时调用

本文件的对外接口：
1、exwin.open(config)                ：打开一个新窗口，自动分配ID并执行创建回调
2、exwin.close(win_id)               ：关闭指定窗口及其全部后代（通常用于关闭自己）
3、exwin.is_active(win_id)           ：查询窗口是否为当前活动窗口
4、exwin.return_idle()               ：一键返回首页（ID=1），销毁其他所有窗口
5、【v2.0】exwin.close_children_of(id)：销毁 id 的全部后代（不含 id 自身），用于一级菜单切换
6、【v2.0】exwin.close_family(id)     ：销毁 id 及其全部后代
7、【v2.0】exwin.find_root(win_id)    ：向上追溯 win_id 所属的一级菜单（根）窗口 id
8、【v2.0】exwin.has_children(id)     ：查询 id 是否存在子窗口
9、【v2.0】exwin.get_owner(win_id)    ：查询 win_id 的归属者 id（顶层窗口返回 nil）
10、【v2.1】exwin.begin_menu_switch(id)：声明一次一级菜单切换事务，由 exwin 在新页创建完成后回收旧页
11、【v2.1】exwin.children_of(id)      ：列出 id 的全部直接子窗口 id
12、【v2.2】exwin.bind_root(root,opts) ：把页面根控件登记到当前窗口，被盖住时自动隐藏

关于 root（页面根控件）：
- 登记后，只有栈顶窗口与 keep_visible 的窗口会显示根控件，其余一律隐藏；
- 显隐统一由 exwin 在开窗/关窗/焦点结算时收敛，调用方无需自行管理；
- 未登记 root 的窗口行为与 v2.1 完全一致。

关于 owner（归属者）：
- exwin.open({...}) 未显式指定 owner 时，默认取**开窗时的栈顶窗口 id**，即「谁开的我，我就归谁」。
- 顶层窗口（owner == nil）就是一级菜单页面。
- 若首页 idle_win 在切菜单前先清空自己的子树，则新一级菜单页面的 owner 会自动落到 idle 上，
  二级页面（设置里的 iot 等）的 owner 会自动落到其父页面（设置）上，无需调用方手写层级数字。

-- 版本更新说明
-- 版本号：202610221800
-- 1、更新时间：2026-10-22 18:00
-- 2、更新内容
--    新增 exwin.bind_root(root, opts)：把页面根控件登记到当前窗口，被盖住时自动隐藏、回到它时再显示。
--    根因：exwin 此前只改焦点，不改绘制参与度，被盖住的页面控件原样留在活动屏上。
--    宽屏带左栏（页面根只占右侧内容区）时，整屏失效无法被 LVGL 的顶层全覆盖裁剪命中，
--    下层页面会跟着整棵重画一遍。隐藏根控件后既省绘制，也顺带挡掉触摸命中。
--    兼容性：未登记 root 的窗口行为完全不变；新增字段仅写入窗口记录，不改动任何既有回调的顺序与签名。
-- 版本号：202609171720
-- 1、更新时间：2026-09-17 17:20
-- 2、更新内容
--    新增 begin_menu_switch / children_of：把「回收旧菜单」推迟到新页面创建完成之后执行，
--    消除一级菜单切换时「先闪一下宿主桌面、再进入新页面」的问题。
--    根因：sys.publish 只是把消息压入全局队列（script/corelib/sys.lua:524），
--    真正的分发发生在 sys.run() 的下一轮 dispatch，本轮结束时会先渲染一帧。
--    新增 owner 归属字段与 close_children_of / close_family / find_root / has_children / get_owner
--    支持一级菜单切换时精准销毁其整棵子树，将窗口栈深度由「无上界」变为「可推导上界」
--    新增版本号管理接口 exwin.version()（202607021200 版本引入）
]]

local exwin = {}

-- 窗口栈，栈顶为当前活动窗口
local win_stack = {}
-- 下一个可分配的窗口ID（从1开始）
local next_id = 0

--[[焦点抑制标志

批量销毁（close_children_of / close_family）期间置为 true，
避免每移除一个窗口就结算一次焦点（否则会触发 N 次页面重建，
例如 idle_win 的换肤重建会被反复触发）。批量结束后统一结算一次。]]
local suppress_focus = false

--[[待执行的「一级菜单切换」事务（由 exwin.begin_menu_switch 登记）

结构：{ host = 宿主窗口id, victims = 待回收的旧后代id列表（子先于父）, timer = 超时兜底定时器 }
被 exwin.open 消费：消费时强制新窗归属 host，并在新窗 create 完成后回收 victims。]]
local switch_pending = nil

--[[内部函数：根据ID查找窗口在栈中的索引

@local
@function find_index_by_id
@param id number 窗口ID
@return number|nil 窗口在栈中的索引，若不存在返回nil
]]
local function find_index_by_id(id)
    for i, w in ipairs(win_stack) do
        if w.id == id then
            return i
        end
    end
    return nil
end

--[[内部函数：实际执行根控件的隐藏/显示

单独拆出是为了让 pcall 能整体兜住：
控件已 destroy、方法不存在、userdata 索引失败等情况都不应影响窗口栈逻辑。]]
local function do_set_root_hidden(root, hidden)
    root:set_hidden(hidden)
end

--[[内部函数：隐藏或显示页面根控件

只用 set_hidden，不调用 open()：open() 除了清除 HIDDEN 还会把控件挪到父容器最上层，
在「恢复显示」时会翻掉页面之间的层级关系。

@local
@function set_root_hidden
@param root userdata|table 页面根控件
@param hidden boolean true=隐藏
]]
local function set_root_hidden(root, hidden)
    if root == nil then return end
    pcall(do_set_root_hidden, root, hidden and true or false)
end

--[[内部函数：按窗口栈收敛所有已登记根控件的显隐

只有栈顶窗口与 keep_visible 的窗口保持显示，其余隐藏。
幂等：重复调用结果一致，因此可以在开窗、关窗、焦点结算等任意时机调用，
不必区分「隐藏下层」和「显示自己」两条路径。

@local
@function sync_root_visibility
]]
local function sync_root_visibility()
    if suppress_focus then return end
    local top = win_stack[#win_stack]
    for _, w in ipairs(win_stack) do
        if w.root then
            local want = (w == top) or (w.keep_visible == true)
            if w.root_shown ~= want then
                set_root_hidden(w.root, not want)
                w.root_shown = want
            end
        end
    end
end

--[[内部函数：结算焦点

把焦点交给当前栈顶。suppress_focus 为真时跳过
（批量销毁期间由调用者在收尾时手动结算一次）。
焦点结算前后各收敛一次根控件显隐：
之前的那次把新栈顶显示出来，之后的那次兜住 on_get_focus 里重建了根控件的情况。]]
local function settle_focus()
    if suppress_focus then return end
    sync_root_visibility()
    local top = win_stack[#win_stack]
    if top and top.get_focus then
        pcall(top.get_focus)
    end
    sync_root_visibility()
end

--[[内部函数：递归收集 id 的全部后代（不含 id 自身）

acc 中**子先于父**入表，因此天然形成「自底向上」的销毁顺序：
先销毁最深的孙子，再销毁子，避免中途出现「父已销毁、子仍持有 owner 指向它」的孤儿状态。

@local
@function collect_descendants
@param id number 根窗口ID
@param acc table 结果累加表（会被就地修改）
@return table acc
]]
local function collect_descendants(id, acc)
    for _, w in ipairs(win_stack) do
        if w.owner == id then
            collect_descendants(w.id, acc)
            acc[#acc + 1] = w.id
        end
    end
    return acc
end

--[[内部函数：销毁一组窗口（调用 destroy 回调并出栈）

入参 victim 需为「子先于父」顺序。
返回是否影响过原栈顶（用于决定是否需要重新结算焦点）。

@local
@function destroy_many
@param victim table 待销毁的窗口 id 列表（子先于父）
@return boolean 被销毁的窗口中是否包含原栈顶
]]
local function destroy_many(victim)
    local old_top = win_stack[#win_stack]
    local top_affected = false
    if old_top then
        for _, vid in ipairs(victim) do
            if vid == old_top.id then
                top_affected = true
                break
            end
        end
    end

    for _, vid in ipairs(victim) do
        local vi = find_index_by_id(vid)
        if vi then
            local w = win_stack[vi]
            if w.destroy then
                pcall(w.destroy)
            end
            -- 根控件随窗口销毁，立刻断开引用，避免后续 sync 误操作已销毁的控件
            w.root = nil
            w.root_shown = nil
            w.keep_visible = nil
            table.remove(win_stack, vi)
        end
    end
    return top_affected
end

--[[
打开一个新窗口

@api exwin.open(config)
@table config 配置表，可包含：
    @function on_create 窗口创建回调（必需）
    @function on_destroy 窗口销毁回调（必须）
    @function on_lose_focus 窗口失去焦点回调（可选）
    @function on_get_focus 窗口获得焦点回调（可选）
    @number   owner 归属者窗口ID（可选）
            不传时默认取开窗瞬间的栈顶窗口ID，即「谁开的我，我就归谁」；
            传 false 表示显式声明为顶层窗口（owner = nil）。
@return number 新窗口的ID
@usage
local win_id = exwin.open({
    on_create = function() print("窗口创建") end,
    on_get_focus = function() print("窗口获得焦点") end,
    on_lose_focus = function() print("窗口失去焦点") end,
    on_destroy = function() print("窗口销毁") end
})
]]
function exwin.open(config)

    -- 如果参数不是表则报错重启
    assert(type(config) == "table" and type(config.on_create) == "function" and type(config.on_destroy) == "function", "exwin.open()参数必须是table，并且包含on_create函数")

    -- 获取当前活动窗口（栈顶）
    local current = win_stack[#win_stack]

    -- 分配新ID
    next_id = next_id + 1
    local new_id = next_id

    -- 归属者：显式传入优先；传 false 表示顶层；菜单切换事务期间强制归属宿主；
    -- 未传则默认归属当前栈顶（即「谁开的我，我就归谁」）
    local owner
    if config.owner == false then
        owner = nil
    elseif config.owner ~= nil then
        owner = config.owner
    elseif switch_pending then
        -- 菜单切换中：旧菜单此时尚未回收，栈顶还是它。若不强制归属宿主，
        -- 新页面会挂到旧菜单名下，随即被本次切换的回收动作连带销毁。
        owner = switch_pending.host
    else
        owner = current and current.id or nil
    end

    -- 构造窗口记录
    local new_win = {
        id = new_id,
        owner = owner,
        create = config.on_create,
        destroy = config.on_destroy,
        lose_focus = config.on_lose_focus,
        get_focus = config.on_get_focus
    }

    -- 如果存在当前窗口，先隐藏它的根控件，再让其失去焦点
    --（keep_visible 的窗口即使被盖住也要露出，例如桌面的左栏）
    if current then
        if not current.keep_visible then
            set_root_hidden(current.root, true)
            current.root_shown = false
        end
        if current.lose_focus then
            pcall(current.lose_focus)
        end
    end

    -- 新窗口入栈
    table.insert(win_stack, new_win)

    -- 调用新窗口的创建回调
    pcall(new_win.create)

    --[[菜单切换事务的后半程：回收旧菜单的整棵子树。

    必须放在新窗口 create **之后**：此时新窗口已入栈、其控件已挂到屏幕最上层，
    旧菜单整棵树被压在下面，销毁它不会有任何一帧露出宿主（idle_win）。
    这一点由 sys.publish 的语义决定 —— publish 只是把消息压进全局队列，
    真正的分发在 sys.run() 的下一轮 dispatch，本轮结束时会先渲染一帧；
    若沿用「先清后开」，那一帧渲染的就是被清空后裸露的桌面，即切换闪烁。]]

    if switch_pending then
        local sw = switch_pending
        switch_pending = nil
        if sw.timer then sys.timerStop(sw.timer) end
        if #sw.victims > 0 then
            suppress_focus = true
            destroy_many(sw.victims)
            suppress_focus = false
            -- 不结算焦点：栈顶就是刚创建的新页面，本就是它该在的位置。
            --（sw.victims 中不含栈顶，destroy_many 内部的 top_affected 亦为 false）
        end
    end

    -- 收敛根控件显隐：新窗口已建好自己的根控件，这里一并把它显示出来、压住其余页面
    sync_root_visibility()

    return new_id
end

--[[
关闭指定窗口及其全部后代（通常由页面自己调用）

@api exwin.close(win_id)
@param win_id number 要关闭的窗口ID
@return nil
@usage
-- 在窗口内部关闭自己
exwin.close(win_id)
]]
function exwin.close(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return end

    -- 自身 + 全部后代，自底向上销毁（后代入表顺序为子先于父）
    local victim = collect_descendants(win_id, {})
    victim[#victim + 1] = win_id

    local top_affected = destroy_many(victim)

    -- 若原栈顶在销毁集合内，则让新的栈顶获得焦点
    if top_affected then
        settle_focus()
    end
    -- 否则焦点窗口未受影响，无需额外操作
end

--[[
销毁指定窗口的全部后代（不含 win_id 自身）

典型用法：一级菜单页面（如 idle_win）在切换到别的内置应用前，先清掉
上一个应用留下的整棵子树（设置 → 设置里的 iot/关于/主题 …）。

@api exwin.close_children_of(win_id)
@param win_id number 宿主窗口ID
@return number 实际销毁的窗口数量
@usage
exwin.close_children_of(theme.shell.host_id)   -- 切菜单前先清场
sys.publish("OPEN_" .. win .. "_WIN")          -- 再打开新页面
]]
function exwin.close_children_of(win_id)
    if win_id == nil then return 0 end

    local victim = collect_descendants(win_id, {})
    local n = #victim
    if n == 0 then return 0 end

    suppress_focus = true
    destroy_many(victim)
    suppress_focus = false

    -- 批量销毁后统一结算一次焦点。
    -- 这一步不可省：宿主（idle_win）在换肤等场景下依赖 on_get_focus 完成重建，
    -- 若把回调全部抑制且不补结算，会出现「换肤后左栏颜色不刷新」。
    settle_focus()
    return n
end

--[[
销毁指定窗口及其全部后代

等价于 exwin.close(win_id)，保留该接口是为了让「关掉整棵子树」的意图在调用处更直白。

@api exwin.close_family(win_id)
@param win_id number 子树根窗口ID
@return nil
]]
function exwin.close_family(win_id)
    exwin.close(win_id)
end

--[[
向上追溯 win_id 所属的一级菜单（根）窗口 id

@api exwin.find_root(win_id)
@param win_id number 起始窗口ID
@return number|nil 根窗口ID；win_id 本身即顶层时返回自身；窗口不存在返回 nil
@usage
-- 二级页面激活时，左栏需要高亮其所属的一级菜单
local root_id = exwin.find_root(window_id)
]]
function exwin.find_root(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return nil end

    local cur = win_stack[idx]
    local guard = 0
    while cur and cur.owner do
        local oi = find_index_by_id(cur.owner)
        if not oi then break end
        local parent = win_stack[oi]
        if parent == cur then break end  -- 自引用保护
        cur = parent
        guard = guard + 1
        if guard > 64 then break end     -- 环保护
    end
    return cur and cur.id or nil
end

--[[
声明一次「一级菜单切换」事务

一级菜单页面（如 idle_win）在切换到另一个内置应用前调用本接口，随后再 publish 目标页的开窗事件。
本接口让 exwin 接管「回收旧菜单」这一步，并把它推迟到**新页面创建完成之后**执行，
从而消除切换瞬间的闪烁。

为什么不能由调用方自己「先清后开」：
sys.publish 只是把消息压入全局消息队列（script/corelib/sys.lua:524），
真正的分发发生在 sys.run() 的下一轮 dispatch。调用方在 publish 之后本轮就结束了，
渲染会先跑一帧 —— 若此时旧菜单已被销毁，这一帧裸露出来的就是宿主 idle_win。

本接口登记后，exwin 会做两件事：
1. 紧接着的第一个 exwin.open 强制归属 host_id（否则会挂到尚未回收的旧菜单页上）；
2. 该窗口创建完成后，立即回收 host_id 的旧后代（此刻已被新页面遮挡，用户不可见）。

@api exwin.begin_menu_switch(host_id)
@param host_id number 一级菜单的宿主窗口ID（如 idle_win 的 window_id）
@return nil
@usage
local host = theme.shell.host_id
exwin.begin_menu_switch(host)          -- 声明切换事务
sys.publish("OPEN_SETTINGS_WIN")       -- 随后正常开窗即可，回收由 exwin 收尾
]]
function exwin.begin_menu_switch(host_id)
    if host_id == nil then return end

    -- 兜底：目标页面若没有订阅者（对应窗口模块未加载），事务不会被消费。
    -- 超时后丢弃，避免残留状态污染后续某个无关窗口的 open。
    -- token 用于识别「当前这一笔事务」：连续两次切换时，先登记的那笔超时后
    -- 不能把后登记的那笔一起清掉，否则后一次切换的回收会静默失效。
    local token = {}
    local timer = sys.timerStart(function()
        if switch_pending and switch_pending.token == token then
            switch_pending = nil
            log.warn("exwin", "menu switch not consumed, dropped")
        end
    end, 1000)

    switch_pending = {
        host = host_id,
        victims = collect_descendants(host_id, {}),
        token = token,
        timer = timer,
    }
end

--[[
列出窗口的全部直接子窗口ID

@api exwin.children_of(win_id)
@param win_id number 父窗口ID
@return table 直接子窗口ID数组（按栈内顺序，自底向上）；无子窗口时返回空表
@usage
-- 一级菜单宿主至多有一个子窗口（各一级菜单互斥）
local leaf = exwin.children_of(theme.shell.host_id)[1]
]]
function exwin.children_of(win_id)
    local out = {}
    if win_id == nil then return out end
    for _, w in ipairs(win_stack) do
        if w.owner == win_id then
            out[#out + 1] = w.id
        end
    end
    return out
end

--[[
查询窗口是否存在直接子窗口

@api exwin.has_children(win_id)
@param win_id number 窗口ID
@return boolean
]]
function exwin.has_children(win_id)
    if win_id == nil then return false end
    for _, w in ipairs(win_stack) do
        if w.owner == win_id then return true end
    end
    return false
end

--[[
查询窗口的归属者 id

@api exwin.get_owner(win_id)
@param win_id number 窗口ID
@return number|nil 归属者窗口ID；顶层窗口返回 nil
]]
function exwin.get_owner(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return nil end
    return win_stack[idx].owner
end

--[[
把页面根控件登记到当前窗口

登记后，该页面被别的窗口盖住时根控件自动隐藏、回到它时自动显示。
必须在窗口的 on_create 里调用（此刻当前窗口就是它自己），或者在 on_get_focus 里重建根控件后再次调用。

hide/show 只做 set_hidden，不改变控件的层级顺序；控件已销毁时静默跳过。

@api exwin.bind_root(root, opts)
@param root userdata|table 页面根控件，传 nil 解除登记
@param table opts 可选配置，可包含：
    @boolean keep_visible 为 true 时即使被盖住也保持显示（如桌面需要露出左侧栏）
@return boolean 是否登记成功（栈为空时返回 false）
@usage
-- 页面自己创建完根控件后登记
main_container = theme.page_bg(parent, ...)
exwin.bind_root(main_container)

-- 桌面需要被盖住时仍露出左栏
exwin.bind_root(main_container, { keep_visible = true })
]]
function exwin.bind_root(root, opts)
    local top = win_stack[#win_stack]
    if not top then return false end

    -- 换了根控件才需要重置显隐状态，重复登记同一根控件时保持幂等
    if top.root ~= root then
        top.root = root
        top.root_shown = nil
    end
    top.keep_visible = (type(opts) == "table" and opts.keep_visible == true) or nil

    sync_root_visibility()
    return true
end

--[[
查询窗口是否为当前活动页面

@api exwin.is_active(win_id)
@param win_id number 窗口ID
@return boolean true表示是活动窗口，false表示不是或窗口不存在
@usage
if exwin.is_active(1) then
    log.info("首页是活动窗口")
end
]]
function exwin.is_active(win_id)
    if win_id == nil then return false end
    local current = win_stack[#win_stack]
    return current and current.id == win_id
end

--[[
一键返回首页（win_id=1），销毁其他所有窗口，并保留第一个窗口

@api exwin.return_idle()
@return nil
@usage
-- 在任何页面调用，都会回到首页并销毁中间页面
exwin.return_idle()
]]
function exwin.return_idle()
    -- 从栈顶向下遍历，销毁除栈底（第一个窗口）外的所有窗口
    -- 栈底窗口的ID应为1（假设第一个打开的窗口是首页）
    if #win_stack <= 1 then
        settle_focus()
        return
    end

    local victim = {}
    for i = #win_stack, 2, -1 do
        victim[#victim + 1] = win_stack[i].id
    end

    suppress_focus = true
    destroy_many(victim)
    suppress_focus = false

    -- 现在栈中只剩首页（索引1），调用其获得焦点回调
    settle_focus()
end

--[[
获取窗口栈调试快照（供日志/自检使用，不参与业务逻辑）

返回的是可 json 编码的字段，root 以布尔量形式给出（控件对象本身无法序列化）。

@api exwin.dump()
@return table { {id=, owner=, index=, root_bound=, keep_visible=}, ... } 自底向上的窗口列表
@usage
log.info("exwin", "stack =", json.encode(exwin.dump()))
]]
function exwin.dump()
    local out = {}
    for i, w in ipairs(win_stack) do
        out[#out + 1] = {
            id = w.id,
            owner = w.owner,
            index = i,
            root_bound = w.root ~= nil,
            keep_visible = w.keep_visible == true,
        }
    end
    return out
end

--[[
获取当前栈深度

@api exwin.depth()
@return number 栈中窗口数量
]]
function exwin.depth()
    return #win_stack
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202609171630"
@usage
exwin.version()
]]
function exwin.version()
    return "202610221800"
end

log.debug("exwin", "version -> " .. exwin.version())

return exwin
