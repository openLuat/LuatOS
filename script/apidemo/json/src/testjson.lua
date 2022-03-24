local testjson = {}

local sys = require "sys"

sys.taskInit(function()
    local t = {
        a = 1,
        b = "abc",
        c = {
            1,2,3,4
        },
        d = {
            x = false,
            j = 111111
        },
        aaaa = 6666,
    }
    
    local s = json.encode(t)
    
    local st = json.decode(s)
    
    print(s)
    print(st.a,st.b,st.d.x)
    while true do
        sys.wait(1000)
    end

end)

return testjson