--[[
@module  gmssl_sm2
@summary gmssl_sm2 
@version 1.0
@date    2025.10.29
@author  沈园园
@usage
本文件为gmssl sm2应用功能模块，核心业务逻辑为：
1、演示国密sm2加密和解码的应用；

本文件没有对外接口，直接在main.lua中require "gmssl_sm2"就可以加载运行；
]]


function gmssl_sm2_encrypt_decrypt(originStr, pkx, pky, private)
    -- GMSSL默认格式
    log.info("==== SM2 默认GMSSL模式")
    local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr)
    log.info("sm2默认模式", "加密后", encodeStr and  string.toHex(encodeStr))
    if encodeStr then
        log.info("sm2默认模式", "解密后", gmssl.sm2decrypt(private,encodeStr))
    end
    

    -- 网站兼容模式 https://i.goto327.top/CryptTools/SM2.aspx
    -- 密文格式 C1C3C2, 新国标, 一般是这种
    log.info("==== SM2 网站兼容模式")
    local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr, true)
    log.info("sm2网站兼容模式 C1C3C2", "加密后", encodeStr and  string.toHex(encodeStr))
    if encodeStr then
        log.info("sm2网站兼容模式 C1C3C2", "解密后", gmssl.sm2decrypt(private,encodeStr, true))
    else
        log.info("解密失败")
    end
    -- 密文格式 C1C2C3, 老国标, 老的Java库通常支持这种
    log.info("==== SM2 网站兼容模式, 但C1C2C3")
    local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr, true, true)
    log.info("sm2网站兼容模式 C1C2C3", "加密后", encodeStr and  string.toHex(encodeStr))
    if encodeStr then
        log.info("sm2网站兼容模式 C1C2C3", "解密后", gmssl.sm2decrypt(private,encodeStr, true, true))
    else
        log.info("解密失败")
    end
end


local function gmssl_sm2_task_func()
    -- 未加密字符串
    local originStr = "!!from LuatOS!!"

    -- SM2 , 非对称加密, 类似于RSA,但属于椭圆算法
    -- 就当前实现还是比较慢的
    if gmssl.sm2encrypt then -- 部分BSP不支持
        local pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
        local pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
        local private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
        gmssl_sm2_encrypt_decrypt(originStr, pkx, pky, private)
    end

    -- SM密钥生成
    if gmssl.sm2keygen then
        log.info("SM2密钥生成测试")
        originStr = "32wrniosadnfvnadsio;fasiow"
        local pkx, pky, private = gmssl.sm2keygen()
        gmssl_sm2_encrypt_decrypt(originStr, pkx, pky, private)
    end

end

sys.taskInit(gmssl_sm2_task_func)

