
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "crypto_gcm"
VERSION = "1.0.0"


sys.taskInit(function()
    -- 测试GCM加解密
    local key = "0123456789abcdef" -- 16字节密钥
    local iv = "abcdef9876543210"  -- 16字节初始向量
    local plaintext = "Hello, LuaTools! This is a test message for GCM encryption."
    log.info("Plaintext:", plaintext)
    -- 加密
    local ciphertext, tag = crypto.cipher_encrypt("AES-128-GCM", "NONE", plaintext, key, iv)
    log.info("Ciphertext (hex):", string.toHex(ciphertext))
    log.info("Tag (hex):", string.toHex(tag))
    -- 解密
    local decrypted_text = crypto.cipher_decrypt("AES-128-GCM", "NONE", ciphertext, key, iv, tag)
    log.info("Decrypted Text:", decrypted_text)

    log.info("GCM Encryption/Decryption Test Completed")
    -- 对照一下网页上的加密结果
    -- https://www.devglan.com/online-tools/aes-encryption-decryption
    -- 注意, 这个网站的GCM加密结果是把tag附加在密文后面的
    log.info("is same?", decrypted_text == plaintext)
    -- B23DD8E88600EEEE384EECC036ED5DDF51AB7CBCC73A3B53E2B63155867CDC4459C82F00070970609040B880AED39353A3F2DDD1D90E2284D26544
    -- B23DD8E88600EEEE384EECC036ED5DDF51AB7CBCC73A3B53E2B63155867CDC4459C82F00070970609040B880AED39353A3F2DDD1D90E2284D26544
    log.info("is same?", string.toHex(ciphertext) == "B23DD8E88600EEEE384EECC036ED5DDF51AB7CBCC73A3B53E2B63155867CDC4459C82F00070970609040B880AED39353A3F2DDD1D90E2284D26544")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
