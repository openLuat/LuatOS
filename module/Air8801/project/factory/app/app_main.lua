-- Air8801 本机设置。硬件操作由对应的测试页触发。
local M = {}

function M.core()
    require "status_provider_app"
    require "settings_about_app"
    require "settings_display_app"
    require "settings_time_app"
    require "settings_storage_app"
    require "settings_memory_app"
    require "file_manager_app"
end

return M
