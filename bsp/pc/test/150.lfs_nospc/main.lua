--[[
@module  io
@summary 压力测试: 大量小文件 (8字节文件名, 1KB数据)
@author  Wendal Chen
@date    2025.07.14
]]

local sys = require "sys"

local TEST_PATH = "/lfs2/"
local BLOCK_SIZE = 4096
local _, total_blk, init_used = io.fsstat(TEST_PATH)

print("===== 大量小文件压力测试 =====")
print(string.format("分区: %d blocks (%.1f KB), 初始占用 %d blocks", total_blk, (total_blk*BLOCK_SIZE)/1024, init_used))
print("文件: 8字节名 + 1KB数据, 目标 1024 个")
print("")

sys.taskInit(function()

local data = string.rep("A", 1024)
local count = 0
local last_used = init_used
local last_meta = 0
local last_report = 0
local PER_REPORT = 10  -- 每 10 个文件报告一次

print(string.format("%-6s %-8s %-8s %-8s %-10s %s",
    "文件数", "used", "data_blk", "meta_blk", "meta/文件", "备注"))

local start_time = os.clock()

while count < 1024 do
    local fname = TEST_PATH .. string.format("f%04d.bin", count + 1)
    local f = io.open(fname, "wb")
    if not f then
        print(string.format("  open 失败! 第 %d 个文件", count + 1))
        break
    end
    local ok = f:write(data)
    if not ok then
        print(string.format("  write 失败! 第 %d 个文件", count + 1))
        f:close()
        break
    end
    f:close()

    count = count + 1

    if count % PER_REPORT == 0 then
        local _, _, used = io.fsstat(TEST_PATH)
        local data_blks = count * 1  -- 每个 1KB = ceil(1024/4096) = 1 data block
        local meta_blks = used - init_used - data_blks
        local meta_per = meta_blks / count
        local note = ""
        if meta_blks ~= last_meta then
            note = string.format("<< meta +%d", meta_blks - last_meta)
        end
        print(string.format("%-6d %-8d %-8d %-8d %-10.2f %s",
            count, used, data_blks, meta_blks, meta_per, note))
        last_used = used
        last_meta = meta_blks
        last_report = count
    end

    sys.wait(1)
end

local elapsed = os.clock() - start_time

-- 最终状态
local _, _, final_used = io.fsstat(TEST_PATH)
local data_blks = count * 1
local meta_blks = final_used - init_used - data_blks

print("")
print(string.format("===== 结果: %d 个文件 =====", count))
print(string.format("总 used:   %d blocks (%.1f KB)", final_used, (final_used*BLOCK_SIZE)/1024))
print(string.format("数据块:    %d blocks (%.1f KB)", data_blks, (data_blks*BLOCK_SIZE)/1024))
print(string.format("元数据:    %d blocks (%.1f KB)", meta_blks, (meta_blks*BLOCK_SIZE)/1024))
print(string.format("每文件:    %.2f blocks (%.0f 字节)", (final_used - init_used) / count, ((final_used - init_used) * BLOCK_SIZE) / count))
print(string.format("耗时:      %.1f 秒", elapsed))
print(string.format("总容量:    %d blocks (%.1f KB), 利用率: %.1f%%",
    total_blk, (total_blk*BLOCK_SIZE)/1024, (data_blks / total_blk) * 100))

end)
sys.run()