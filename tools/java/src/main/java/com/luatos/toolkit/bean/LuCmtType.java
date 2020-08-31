package com.luatos.toolkit.bean;

public enum LuCmtType {

    /**
     * Lua 模块抬头部分
     * 
     * <pre>
     * /&lowast; 
     * &otimes;module  ctiot
     * &otimes;summary 中国电信CTIOT集成
     * &otimes;version 1.0
     * &otimes;date    2020.08.30
     * &lowast;/
     * </pre>
     */
    LUA_HEAD,

    /**
     * 标识了 Lua 的特殊注释
     * 
     * <pre>
     * /&lowast; 
     * 显示屏初始化
     * &otimes;api disp.init(conf)
     * ...
     * </pre>
     * 
     */
    LUA_SIGN,

    /**
     * 多行注释
     * 
     * <pre>
     * /&lowast; 
     * &otimes;xxxxx
     * &otimes;xxxxx
     * &otimes;xxxxx
     * &lowast;/
     * </pre>
     * 
     * 当然，也可以是
     * 
     * <pre>
     * /&lowast; 
     *  &lowast; &otimes;xxxxx
     *  &lowast; &otimes;xxxxx
     *  &lowast; &otimes;xxxxx
     *  &lowast;/
     * </pre>
     */
    BLOCK,

    /**
     * 单行注释
     * 
     * <pre>
     * // xxxx
     * </pre>
     */
    LINES

}
