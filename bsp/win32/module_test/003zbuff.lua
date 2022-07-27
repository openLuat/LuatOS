local buff = zbuff.create(15,6)
for i=0,14 do
    log.info("read byte",i,buff[i])
    assert(buff[i] == 6,"init error")
end

local writeLen = buff:write("abcde")
log.info("writeLen string",writeLen)
assert(writeLen == 5,"string write length error")
writeLen = buff:write(0x31,0x32,0x33,0x34,0x35)
log.info("writeLen numbers",writeLen)
assert(writeLen == 5,"numbers write length error")

buff:seek(0)
local readData = buff:read(5)
log.info("readData1",readData)
assert(readData == "abcde","read data1 error")
readData = buff:read(5)
log.info("readData2",readData)
assert(readData == "12345","read data2 error")

log.info("write bytes")
for i=0,9 do
    buff[i] = i * 2
end

for i=0,9 do
    log.info("read byte",i,buff[i])
    assert(buff[i] == i * 2,"read byte error")
end

buff:seek(0)
writeLen = buff:pack(">bbbIAIII",1,2,3,4,"abc",666,2,3)
log.info("pack write length",writeLen)
assert(writeLen == 15,"pack write length error")

buff:seek(0)
local len,b1,b2,b3,b4,s,i1 = buff:unpack(">bbbIA3III")
log.info("unpack read",len,b1,b2,b3,b4,s,i1)
assert(len == 14,"pack read length error")
assert(b1 == 1,"pack read b1 error")
assert(b2 == 2,"pack read b2 error")
assert(b3 == 3,"pack read b3 error")
assert(b4 == 4,"pack read b4 error")
assert(s == "abc","pack read s error")
assert(i1 == 666,"pack read I error")

local buff = zbuff.create(30,0)
buff:del()
assert(buff:used() == 0,"del error")
buff:resize(1024)
assert(buff:len() == 1024,"resize error")
buff:copy(nil, "123")
assert(buff:used() == 3,"copy error")
assert(buff:query() == "123","query error")
buff:set(1,0x30,1)
assert(buff:query() == "103","set error")
buff:set(0,0x30,3)
assert(buff:query() == "000","set error")
buff:copy(0, 0x12,0x34,0x56,0x78)
assert(buff:used() == 4,"copy error")
assert(buff:query(0, 4, true) == 0x12345678,"query error")
assert(buff:query(0, 2, true) == 0x1234,"query error")

assert(buff[2] == 0x56,"copy error")
local buff2 = zbuff.create(16)
buff2:set(0, 0xaa)
buff2:seek(0,zbuff.SEEK_END)
buff:copy(2, buff2)
assert(buff:used() == 18,"copy error")
assert(buff[3] == 0xaa,"copy error")
buff:del(-1)
assert(buff:used() == 17,"del error")
