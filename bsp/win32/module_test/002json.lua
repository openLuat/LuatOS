
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
    aaaa = 6666
}

local s = json.encode(t)
log.info("json",s)

local st = json.decode(s)


for i,j in pairs(t) do
    if type(j) == "number" or type(j) == "string" or type(j) == "boolean" then
        assert(j==st[i],i,"json decode error")
        log.info("check",i,st[i])
    else
        for ii,jj in pairs(j) do
            if type(jj) == "number" or type(jj) == "string" or type(jj) == "boolean" then
                assert(jj==st[i][ii],i,"json decode error")
                log.info("check",i,ii,st[i][ii])
            end
        end
    end
end

