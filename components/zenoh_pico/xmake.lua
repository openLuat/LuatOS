-- SPDX-License-Identifier: MIT
-- 由BSP显式启用；依赖外置、固定提交，不自动下载或改动依赖树。
function main(target, component)
    local root = os.getenv("ZENOH_PICO_ROOT")
    assert(root and root ~= "", "LUAT_USE_ZENOH_PICO=y requires ZENOH_PICO_ROOT")
    root = path.absolute(root)
    local pin = "e83d39b4415f6897e8d6c3b3b651ca88a05f4a17"
    local head = os.iorunv("git", {"-C", root, "rev-parse", "HEAD"}):trim()
    assert(head == pin, "zenoh-pico must be pinned to 1.9.0 " .. pin)
    os.runv("git", {"-C", root, "diff", "--exit-code"})
    os.runv("git", {"-C", root, "diff", "--cached", "--exit-code"})
    component = component or os.scriptdir()
    target:add("defines", "LUAT_USE_ZENOH_PICO=1", "ZENOH_GENERIC", "ZENOH_C_STANDARD=11")
    local _, toolkind = target:tool("cc")
    if toolkind == "clang" then target:add("defines", "ZENOH_COMPILER_CLANG")
    elseif toolkind == "cl" then target:add("defines", "ZENOH_COMPILER_MSVC")
    else target:add("defines", "ZENOH_COMPILER_GCC") end
    target:add("includedirs", path.join(component, "include"), path.join(root, "include"))
    local areas = {"api", "collections", "link", "net", "protocol", "runtime", "session", "transport", "utils", "system/common"}
    local names = os.iorunv("git", {"-C", root, "ls-tree", "-r", "--name-only", "HEAD"})
    for name in names:gmatch("[^\r\n]+") do
        if name:endswith(".c") then
            for _, area in ipairs(areas) do
                if name:startswith("src/" .. area .. "/") then
                    target:add("files", path.join(root, name)); break
                end
            end
        end
    end
    target:add("files", path.join(component, "src", "*.c"))
end
