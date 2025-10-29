local function crypto_task_func()
    
    -- 计算CRC16_IBM
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("IBM",originStr)
    log.info("crc16_IBM", crc16)
    -- 计算CRC16_MAXIM
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("MAXIM",originStr)
    log.info("crc16_MAXIM", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("USB",originStr)
    log.info("crc16_USB", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("MODBUS",originStr)
    log.info("crc16_MODBUS", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("CCITT",originStr)
    log.info("crc16_CCITT", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("CCITT-FALSE",originStr)
    log.info("crc16_CCITT-FALSE", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("X25",originStr)
    log.info("crc16_X25", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("XMODEM",originStr)
    log.info("crc16_XMODEM", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("DNP",originStr)
    log.info("crc16_DNP", crc16)
    -- 计算CRC16_modbus
    local originStr = "123456sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc16 = crypto.crc16("USER-DEFINE",originStr)
    log.info("crc16_USER-DEFINE", crc16)
    
    -- 计算CRC16 modbus
    local crc16 = crypto.crc16_modbus("123456sdfdsfdsfdsffdsfdsfsdfs1234")
    log.info("crc16", crc16)
    crc16 = crypto.crc16_modbus("123456sdfdsfdsfdsffdsfdsfsdfs1234", 0xFFFF)
    log.info("crc16", crc16)
    
    -- 计算CRC32
    local data = "123456sdfdsfdsfdsffdsfdsfsdfs1234" 
    local crc32 = crypto.crc32(data)
    log.info("crc32", crc32) --21438764
    -- start和poly可选, 是 2025.4.14 新增的参数
    local crc32 = crypto.crc32(data, 0xFFFFFFFF, 0x04C11DB7, 0xFFFFFFFF) --等同于crypto.crc32(data)
    log.info("crc32", crc32)

    -- 计算CRC8
    local data= "sdfdsfdsfdsffdsfdsfsdfs1234"
    local crc8 = crypto.crc8(data)
    log.info("crc8", crc8)
    local crc8 = crypto.crc8(data, 0x31, 0xff, false)
    log.info("crc8", crc8)  
        
    log.info("随机数测试")
    for i=1, 10 do
        sys.wait(100)
        log.info("crypto", "真随机数",string.unpack("I",crypto.trng(4)))
        -- log.info("crypto", "伪随机数",math.random()) -- 输出的是浮点数,不推荐
        -- log.info("crypto", "伪随机数",math.random(1, 65525)) -- 不推荐
    end

    log.info("crypto", "ALL Done")
    sys.wait(100000)
end    

--创建一个task，并且运行task的主函数crypto_task_func
sys.taskInit(crypto_task_func)
