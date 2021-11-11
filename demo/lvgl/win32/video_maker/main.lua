
local w = 240

local dataA = string.char(0xFF, 0x00):rep(w*10)
local dataB = string.char(0xFF, 0xFF):rep(w*10)
local dataC = string.char(0x00, 0xFF):rep(w*10)

local f = io.open("video.bin", "wb")
for i = 1, 240, 1 do
    f:write(dataA)
    f:write(dataB)
    f:write(dataC)
end
f:close()
