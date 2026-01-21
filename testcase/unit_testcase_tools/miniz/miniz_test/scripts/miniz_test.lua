local miniz_test = {}

-- Demo payload from the public miniz sample
local b64_payload = "eAEFQIGNwyAMXOUm+E2+OzjhCCiOjYyhyvbVR7K7IR0l+iau8G82eIW5jXVoPzF5pse/B8FaPXLiWTNxEMsKI+WmIR0l+iayEY2i2V4UbqqPh5bwimyEuY11aD8xeaYHxAquvom6VDFUXqQjG1Fek6efCFfCK0b0LUnQMjiCxhUT05GNL75dFUWCSMcjN3EE5c4Wvq42/36R41fa"
local compressed_demo = b64_payload:fromBase64()
local expected_compressed_len = 156
local expected_uncompressed_len = 235

-- Validate that the demo blob inflates to the documented length
function miniz_test.test_uncompress_demo_blob()
    log.info("miniz_test", "inflate demo blob")
    assert(#compressed_demo == expected_compressed_len, string.format("compressed size mismatch, expected %d, got %d", expected_compressed_len, #compressed_demo))

    local inflated = miniz.uncompress(compressed_demo)
    assert(type(inflated) == "string", "inflate should return string")
    assert(#inflated == expected_uncompressed_len, string.format("inflated size mismatch, expected %d, got %d", expected_uncompressed_len, #inflated))

    -- Ensure the compressed buffer is untouched after use
    assert(#compressed_demo == expected_compressed_len, "compressed buffer mutated after inflate")
    log.info("miniz_test", "demo blob inflate passed")
end

-- Ensure repeated inflations are deterministic
function miniz_test.test_uncompress_idempotent()
    log.info("miniz_test", "inflate determinism")
    local first = miniz.uncompress(compressed_demo)
    local second = miniz.uncompress(compressed_demo)
    assert(first == second, "inflate output should be deterministic for identical input")
    assert(#first == expected_uncompressed_len, "unexpected length on repeated inflate")
    log.info("miniz_test", "inflate determinism passed")
end

-- Invalid input should not crash and should surface failure
function miniz_test.test_uncompress_invalid_blob()
    log.info("miniz_test", "inflate invalid blob")
    local ok, res = pcall(miniz.uncompress, "not-a-valid-deflate-stream")
    assert(not ok or res == nil, "invalid payload should fail inflate")
    log.info("miniz_test", "invalid blob handling passed")
end

return miniz_test
