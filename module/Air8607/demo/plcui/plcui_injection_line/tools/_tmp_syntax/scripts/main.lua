PROJECT = "syntax_check"
VERSION = "1.0.0"

local target = "c:/gitee/LuatOS/module/Air8607/demo/plcui/plcui_injection_line/code/main.lua"
local f, err = loadfile(target)
if f then
    print("SYNTAX OK")
else
    print("SYNTAX FAIL:", err)
end
