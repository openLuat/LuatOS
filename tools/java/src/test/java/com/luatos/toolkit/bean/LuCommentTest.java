package com.luatos.toolkit.bean;

import static org.junit.Assert.*;

import org.junit.Test;
import org.nutz.lang.Files;

public class LuCommentTest {

    @Test
    public void test_lua_0() {
        String input = Files.read("input/cmt_lua_0.txt");
        String expec = Files.read("expec/cmt_lua_0.txt");

        LuComment dc = new LuComment(input);
        assertTrue(dc.isLuaSign());
        assertEquals(0, dc.getSpace());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_multi_0() {
        String input = Files.read("input/cmt_c_multi_0.txt");
        String expec = Files.read("expec/cmt_c_multi_0.txt");

        LuComment dc = new LuComment(input);
        assertTrue(dc.isBlock());
        assertEquals(0, dc.getSpace());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_multi_1() {
        String input = Files.read("input/cmt_c_multi_1.txt");
        String expec = Files.read("expec/cmt_c_multi_1.txt");

        LuComment dc = new LuComment(input);
        assertTrue(dc.isBlock());
        assertEquals(0, dc.getSpace());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_single_0() {
        String input = Files.read("input/cmt_c_single_0.txt");
        String expec = Files.read("expec/cmt_c_single_0.txt");

        LuComment dc = new LuComment(input);
        assertTrue(dc.isLines());
        assertEquals(0, dc.getSpace());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_single_1() {
        String input = Files.read("input/cmt_c_single_1.txt");
        String expec = Files.read("expec/cmt_c_single_1.txt");

        LuComment dc = new LuComment(input);
        assertTrue(dc.isLines());
        assertEquals(2, dc.getSpace());
        assertEquals(expec, dc.toString());
    }

}
