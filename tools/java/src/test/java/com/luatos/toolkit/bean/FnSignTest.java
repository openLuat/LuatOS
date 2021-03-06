package com.luatos.toolkit.bean;

import static org.junit.Assert.*;

import org.junit.Test;
import org.nutz.json.Json;
import org.nutz.lang.Files;

import com.luatos.toolkit.api.FnSignParser;
import com.luatos.toolkit.impl.CFnSignParser;
import com.luatos.toolkit.impl.DoxyFnSignParser;

public class FnSignTest {

    @Test
    public void test_lua_cmt_fn_0() {
        String input = Files.read("input/lua_cmt_fn_0.txt");
        String expec = Files.read("expec/lua_cmt_fn_0.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new DoxyFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_lua_cmt_fn_1() {
        String input = Files.read("input/lua_cmt_fn_1.txt");
        String expec = Files.read("expec/lua_cmt_fn_1.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new DoxyFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_lua_cmt_fn_2() {
        String input = Files.read("input/lua_cmt_fn_2.txt");
        String expec = Files.read("expec/lua_cmt_fn_2.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new DoxyFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_0() {
        String input = Files.read("input/c_sign_fn_0.txt");
        String expec = Files.read("expec/c_sign_fn_0.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_1() {
        String input = Files.read("input/c_sign_fn_1.txt");
        String expec = Files.read("expec/c_sign_fn_1.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_2() {
        String input = Files.read("input/c_sign_fn_2.txt");
        String expec = Files.read("expec/c_sign_fn_2.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_3() {
        String input = Files.read("input/c_sign_fn_3.txt");
        String expec = Files.read("expec/c_sign_fn_3.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_4() {
        String input = Files.read("input/c_sign_fn_4.txt");
        String expec = Files.read("expec/c_sign_fn_4.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        // System.out.println(expFn);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_5() {
        String input = Files.read("input/c_sign_fn_5.txt");
        String expec = Files.read("expec/c_sign_fn_5.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        // System.out.println(expFn);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_6() {
        String input = Files.read("input/c_sign_fn_6.txt");
        String expec = Files.read("expec/c_sign_fn_6.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        // System.out.println(expFn);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_7() {
        String input = Files.read("input/c_sign_fn_7.txt");
        String expec = Files.read("expec/c_sign_fn_7.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        // System.out.println(expFn);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_8() {
        String input = Files.read("input/c_sign_fn_8.txt");
        String expec = Files.read("expec/c_sign_fn_8.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        // System.out.println(expFn);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

}
