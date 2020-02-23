--[[
(
for wsl:
sudo apt update
sudo apt install qemu-user-static
sudo update-binfmts --install i386 /usr/bin/qemu-i386-static --magic '\x7fELF\x01\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x03\x00\x01\x00\x00\x00' --mask '\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xff\xff\xff\xff\xff\xff\xff'
sudo service binfmt-support start
)

install:
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install lua5.3:i386
sudo apt-get install lua5.1
sudo apt-get install luarocks
sudo luarocks install rs232
sudo luarocks install bit32

ps, proxy (for luarocks):
export https_proxy=http://127.0.0.1:1080
export http_proxy=http://127.0.0.1:1080
]]
local help = [[
usage:
download script files:
lua5.1 tool.lua /dev/ttyS8 -d file1 file2 ...
read serial port data:
lua5.1 tool.lua /dev/ttyS8 -r
serial port data after download:
lua5.1 tool.lua /dev/ttyS8 -r -d file1 file2 ...
]]
if #arg < 2 then
    print(help)
    return
end

local rs232 = require "rs232"
local bit = require "bit32"

local p, e = rs232.port(arg[1],{
    baud         = '_115200';
    data_bits    = '_8';
    parity       = 'NONE';
    stop_bits    = '_1';
    flow_control = 'OFF';
    rts          = 'OFF';
})

p:open()

local download,readUart
local files = {}--要下载进去的文件路径
for i=2,#arg do
    if arg[i] == "-d" then
        download = true
    elseif arg[i] == "-r" then
        readUart = true
    else
        table.insert(files,arg[i])
    end
end


--各种要用到的函数

--按位取反，1字节
local function bnot(n)
    local r = 0
    for i=1,8 do
        local b = bit.rshift(n, 8-i) % 2
        b = b == 1 and 0 or 1
        r = r + bit.lshift(b, 8-i)
    end
    return r
end

--计算crc
local function calcrc(s)
    local crc = 0
    for i=1,s:len() do
        crc = bit.bxor(crc, bit.lshift(s:byte(i), 8))
        for j=1,8 do
            if crc >= 0x8000 then
                crc = bit.bxor((bit.lshift(crc, 1) % 0x10000), 0x1021)
            else
                crc = bit.lshift(crc, 1) % 0x10000
            end
        end
        crc = crc % 0x10000
    end
    return math.floor(crc/0x100),crc%0x100
end

local SOH = 0x01
local STX = 0x02
local EOT = 0x04
local ACK = 0x06
local NAK = 0x15
local CAN = 0x18

--xmodem传头
local function xmodem(data,n)
    local data = data..
        string.rep(string.char(0),
            128-data:len())
    return  string.char(SOH,n,bnot(n))..
            data..
            string.char(calcrc(data))
end

--ymodem传文件
local function ymodem(data,n)
    local data = data..
        string.rep(string.char(0x1a),
            1024-data:len())
    return  string.char(STX,n,bnot(n))..
            data..
            string.char(calcrc(data))
end

--取文件名
local function getName(s)
    s = s:gsub("\\","/")
    return s:match(".+/(.+)") or s:match(".+\\(.+)") or s
end

--发某个数据包
local function sendData(s)
    while true do
        p:write(s)
        while true do
            local d = p:read(10,5000)
            --print(d:byte(),d:len(),d)
            if d:byte() == ACK or d:find("C") then return true end--收到了
            if d:byte() == NAK then break end--没收到，再发一遍
            if d:len() == 0 then return end
        end
    end
end


if download then
    print("clear all files, if not response, please restart device")
    while true do
        p:write("reinit\r\n")
        local d = p:read(10,1000)
        if d:find("reinit") then break end
    end
    print("send ry")
    p:write("ry\r\n")
    print("waitting for reply...")
    for i=1,100 do
        local d = p:read(10,1000)
        if d:find("C") then
            print("connect ok!")
            break
        end
    end
    print("start download")
    for i=1,#files do
        --编译
        if files[i]:sub(-4,-1):upper() == ".LUA" then
            local r = files[i]:sub(1,-4).."luac"
            print(r)
            os.execute("luac5.3 -o \""..r.."\" -s \""..files[i].."\"")
            files[i] = r
        end
        local f,e = io.open(files[i],"r")
        if not f then--打开文件失败
            print("file open failed, stop download.",files[i],e)
            return
        end
        local data = f:read("*a") --读取整个文件，以便获取大小
        local name = getName(files[i])
        print("downloading "..name)
        --发送文件名
        if not sendData(xmodem(name..string.char(0)..tostring(data:len()),0)) then
            print("send file name fail") return
        end

        local p,pack = 1,1
        while true do
            local d = data:sub(p,p+1023)
            if d:len() == 0 then break end--读完了
            p = p + 1024
            print((p > data:len() and data:len() or p).."/"..data:len())
            local sd = ymodem(d,pack)
            --print(sd:toHex(),pack)
            if not sendData(sd) then
                print("send file fail") return
            end
            pack = pack + 1
        end
        print("trans end")
        if not sendData(string.char(0x04)) then--结束该文件
            print("end file fail") return
        end
    end
    if not sendData(xmodem("",0)) then--结束
        print("last packet fail") return
    end
    print("all done, reboot")
    p:write("ls\r\n")
    p:write("reboot\r\n")
end


if readUart then
    print("press ctrl+c to kill this tool")
    while true do
        io.write(p:read(1000, 100))
    end
end
p:close()

