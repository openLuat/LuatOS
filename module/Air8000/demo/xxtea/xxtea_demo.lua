--[[
@module  xxtea_demo
@summary xxtea加密算法
@version 1.0
@date    2025.09.25
@author  李源龙
@usage
本demo主要使用xxtea加密算法，对数据进行加密和解密
]]

function xxtea_fnc()
    --判断xxtea库是否存在
    if not xxtea then
        while true do
            sys.wait(1000)
            -- 每隔1秒打印一条信息
            log.info("testCrypto.xxteaTest","xxtea库不存在,请选择带xxtea的固件")
        end
    end
    while true do
        sys.wait(1000)
        --代加密数据
        local text = "Hello World!"
        --key为密钥
        local key = "07946"
        local encrypt_data = xxtea.encrypt(text, key)
        --加密之后打印加密数据，使用toHex()进行16进制显示
        log.info("testCrypto.xxteaTest","xxtea_encrypt:", encrypt_data:toHex())
        local decrypt_data = xxtea.decrypt(encrypt_data, key)
        --解密之后打印解密数据，使用toHex()进行16进制显示
        log.info("testCrypto.xxteaTest","decrypt_data:", decrypt_data:toHex())
    end
end

sys.taskInit(xxtea_fnc)
