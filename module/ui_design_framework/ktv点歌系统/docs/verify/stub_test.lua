-- Offline Lua stub harness for AIR KTV AirUI project.
-- Mocks LuatOS + AirUI globals, loads code1 modules, builds all 9 screens,
-- then simulates interactions to catch runtime errors.
-- Run with: fengari_stub.js

local function warn(...)
    print("[STUB]", ...)
end

-- ============ counters ============
STATS = { widgets=0, items=0, errors=0, clicks=0, maxItems=0 }
WARNS = {}

-- ============ fake widget object ============
local METHODS = {
    "set_hidden","set_color","set_border_color","set_on_click","set_on_long_press",
    "open","hide","move","set_pos","get_pos","destroy","is_destroyed",
    "set_text","set_symbol","get_text","set_font","set_align","set_font_size",
    "set_items","add_item","clear","get_count","set_value","get_value","set_range",
    "set_style","set_state","get_state","set_checked","get_checked","set_on_change",
}
local function newwidget(kind, cfg)
    STATS.widgets = STATS.widgets + 1
    local o = { _kind=kind, _cfg=cfg or {}, _hidden=false, _value=(cfg and cfg.value) or 0,
                _text=(cfg and cfg.text) or "", _items=(cfg and cfg.items) or {} }
    for _, m in ipairs(METHODS) do
        o[m] = function(self, a, b, c)
            if m == "set_text" then
                if type(a) ~= "string" then
                    WARNS[#WARNS+1] = "set_text non-string: " .. tostring(a)
                end
                self._text = a
            elseif m == "set_items" then
                local n = type(a)=="table" and #a or 0
                STATS.items = STATS.items + 1
                if n > STATS.maxItems then STATS.maxItems = n end
                self._items = a or {}
            elseif m == "set_value" then
                if type(a) ~= "number" then WARNS[#WARNS+1]="set_value non-number: "..tostring(a) end
                self._value = a
                if self._on_change then self._on_change(self) end
            elseif m == "get_value" then return self._value
            elseif m == "set_hidden" then self._hidden = a and true or false
            elseif m == "is_destroyed" then return false end
            return true
        end
    end
    if cfg and cfg.on_click then o._click = cfg.on_click end
    if cfg and cfg.on_change then o._on_change = cfg.on_change end
    return o
end

-- ============ mock globals ============
log = setmetatable({
    error = function(self, tag, msg, ...) print("[LOG ERROR]", tag, msg, ...) STATS.errors=STATS.errors+1 end,
    warn  = function() end,
    info  = function() end,
}, {__index=function() return function() end end})

sys = {
    timerStart = function(fn, ms) return 1 end,
    taskInit = function(fn) return 1 end,
    wait = function(ms) end,
    publish = function() end,
    subscribe = function() end,
}

math.randomseed = math.randomseed or function() end

utf8 = utf8 or {}
if not utf8.codes then
    utf8.codes = function(s)
        local i = 1
        return function()
            if i > #s then return nil end
            local c = s:byte(i); local n=1
            if c>=240 then n=4 elseif c>=224 then n=3 elseif c>=192 then n=2 end
            local cp = 0
            for j=0,n-1 do cp = cp*256 + (s:byte(i+j) or 0) end
            local pos = i; i = i + n
            return pos, cp
        end
    end
end

display = { getSize = function() return 1024, 600 end, init = function() return true end }
gpio = setmetatable({}, {__index=function() return function() end end})
i2c  = setmetatable({ SLOW=0 }, {__index=function() return function() end end})
tp   = setmetatable({ FALLING=1 }, {__index=function() return function() return 1 end end})
pwm  = setmetatable({}, {__index=function() return function() return true end end})
wdt  = { init=function() return true end, feed=function() end }

airui = {
    SCREEN_W=1024, SCREEN_H=600, screen=newwidget("screen",{}),
    TEXT_ALIGN_LEFT=0, TEXT_ALIGN_CENTER=1, TEXT_ALIGN_RIGHT=2,
    container=function(c) return newwidget("container",c) end,
    label=function(c) return newwidget("label",c) end,
    shape=function(c) return newwidget("shape",c) end,
    slider=function(c) return newwidget("slider",c) end,
    button=function(c) return newwidget("button",c) end,
    switch=function(c) return newwidget("switch",c) end,
    image=function(c) return newwidget("image",c) end,
    init=function() end, set_rotation=function() end, font_load=function() end,
    device_bind_touch=function() end,
}
-- preloaded core modules (LuatOS semantics: these are built-in, not require'd from disk)
package.loaded["sys"] = sys
-- exwin stub
package.loaded["exwin"] = {
    open=function(cfg) if cfg.on_create then cfg.on_create() end return {id=1} end,
    close=function() end, bind_root=function() end,
}

package.path = "D:/Luatools/code/UI_html/ktv点歌系统/code1/?.lua;" .. package.path
print("[STUB] offline AirUI stub — AIR KTV code1")

local ok, err = pcall(function()
    require "mock"
    require "theme"
    local page = require "page_ktv"
    page.open()

    -- simulate interactions across pages
    local S = require("mock").S
    local pages = {"home","category","artist","search","ordered","rank","playlist","playing","settings"}
    for _, p in ipairs(pages) do
        page.go(p)
    end
    -- ===== exercise real interaction callbacks via recorded on_click =====
    local function click(o, label)
        if o and o._click then local ok,e=pcall(o._click); if not ok then error("click "..label..": "..tostring(e)) end end
    end
    -- add songs, toggle, change song
    page.add(0); page.add(3); page.add(0)   -- includes duplicate path
    page.toggle_play()
    page.change(1); page.change(-1)
    page.replay()
    page.func("next"); page.func("toggle"); page.func("mute")
    page.func("origin"); page.func("atmos")
    -- slider program writes (sync-guard path)
    page.apply_slider("seek", 55)
    page.apply_slider("volume", 40)
    page.apply_slider("setVol", 33)
    page.apply_slider("setBri", 70)
    page.apply_slider("pitch", 60)
    page.apply_slider("micVol", 80)
    -- modal open/close + AC controls
    page.func("eq"); page.close_modal()
    page.func("control")
    page.ac_step("mode", 1); page.ac_step("fan", -1)
    page.ac_set("mode", 3); page.ac_temp(1); page.ac_temp(-1)
    page.ac_set("fan", 2)
    page.close_modal()
    -- func pop
    page.toggle_funcpop(); page.toggle_funcpop()
    -- theme / mode
    page.set_theme("purple"); page.set_theme("cyan"); page.set_theme("blue")
    page.set_mode("light"); page.set_mode("dark")
    require("theme").recolor()
    -- search keyboard: type pinyin & commit candidates by driving key on_click via state
    page.go("search")
    local M = require("mock")
    -- simulate pinyin input state directly (key_press is local, so drive its state effects)
    M.S.pinyin = "gu"; M.S.candPage = 0
    page.go("search")   -- re-render with pinyin buffer
    local cands = M.cands()
    assert(#cands > 0, "pinyin 'gu' should yield candidates")
    M.S.query = M.S.query .. (cands[1] or "")
    M.S.pinyin = ""
    page.go("search")
    M.S.query = "周杰伦"; page.go("search")      -- Chinese search
    local r = M.search(M.S.query)
    assert(#r > 0, "search 周杰伦 should hit")
    M.S.query = "Z"; page.go("search")           -- initial-letter search
    assert(#M.search("Z") > 0, "initial Z should hit")

    -- long-run stability: repeated page switches must not grow widget count
    local before = STATS.widgets
    for i=1,50 do for _, p in ipairs(pages) do page.go(p) end end
    local after = STATS.widgets
    if after ~= before then
        WARNS[#WARNS+1] = "widget count grew on re-render: "..before.." -> "..after
    end
end)

if not ok then
    STATS.errors = STATS.errors + 1
    print("[STUB] FATAL ERROR: " .. tostring(err))
else
    print("[STUB] BUILD OK")
end

print(string.format("[STUB] widgets=%d set_items_calls=%d maxItemsOnOneShape=%d",
    STATS.widgets, STATS.items, STATS.maxItems))
print("[STUB] warnings=" .. #WARNS)
for i=1,math.min(#WARNS,20) do print("  WARN: "..WARNS[i]) end
if STATS.errors > 0 or #WARNS > 0 then
    print("[STUB] RESULT_FAIL")
else
    print("[STUB] RESULT_OK")
end
