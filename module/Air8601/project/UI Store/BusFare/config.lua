return {
    width = 1024,
    height = 600,

    -- 二级页面只有这三个设置项。
    -- digits : 可编辑位数
    -- decimal: 小数点后的位数，0 表示没有小数点
    items = {
        {
            key = "vehicle",
            title = "车辆编号",
            desc = "5 位数字",
            digits = 5,
            decimal = 0,
            unit = ""
        },
        {
            key = "fare",
            title = "票价单价",
            desc = "3 位整数 + 2 位小数",
            digits = 5,
            decimal = 2,
            unit = "元 / 人次"
        },
        {
            key = "warning",
            title = "满胆预警",
            desc = "4 位整数 + 2 位小数",
            digits = 6,
            decimal = 2,
            unit = "元"
        }
    },

    -- 金额统一按“分”保存，例如 200 = 2.00 元，50000 = 500.00 元。
    defaults = {
        vehicle = 8601,
        fare = 200,
        warning = 50000
    }
}
