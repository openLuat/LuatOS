--[[
@module  main
@summary 数据库CRUD测试应用入口（exwin架构）
@version 1.0.1
@date    2026.05.11
@author  合宙
]]

PROJECT = "DB_TEST"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

require "db_test_win"

sys.publish("OPEN_DB_TEST_WIN")

sys.run()
