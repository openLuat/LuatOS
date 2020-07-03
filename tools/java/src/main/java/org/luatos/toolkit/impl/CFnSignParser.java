package org.luatos.toolkit.impl;

import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.luatos.toolkit.api.FnSignParser;
import org.luatos.toolkit.bean.FnModifier;
import org.luatos.toolkit.bean.FnParam;
import org.luatos.toolkit.bean.FnReturn;
import org.luatos.toolkit.bean.FnSign;
import org.nutz.lang.Lang;
import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class CFnSignParser implements FnSignParser {

    private static String _r0 = "^\\s*((static)\\s+)?(\\w+(\\s*[*])?)\\s*(\\w+)\\s*\\(([^)]*)\\).*$";
    private static Pattern PT = Regex.getPattern(_r0);

    private static String _r1 = "^(([\\w\\d]+)(\\s+[*])?)\\s*([\\w\\d]*)$";
    private static Pattern PM = Regex.getPattern(_r1);

    @Override
    public FnSign parse(String block) {
        // 变成一行
        String str = block.replaceAll("\r?\n", " ");

        // 分析
        Matcher m = PT.matcher(str);

        // 不合法
        if (!m.find()) {
            throw Lang.makeThrow("invalid CFunction sign", block);
        }

        // 提取值
        String mod = m.group(2);
        String retp = m.group(3);
        String name = m.group(5);
        String params = m.group(6);

        // 准备返回
        FnSign fn = new FnSign();
        fn.setRawText(block);

        if ("static".equals(mod)) {
            fn.setModifier(FnModifier.STATIC);
        }
        fn.addReturn(new FnReturn(retp));
        fn.setName(name);

        // 分析参数
        String[] ss = Strings.splitIgnoreBlank(params);
        if (ss.length == 0) {
            fn.setParams(new ArrayList<>(0));
        }
        // 循环判断参数
        else {
            for (String s : ss) {
                m = PM.matcher(s);
                if (!m.find()) {
                    throw Lang.makeThrow("invalid CFunction [" + block + "] param", s);
                }
                String pmtp = m.group(1);
                String pmnm = m.group(4);
                FnParam pm = new FnParam();
                pm.setType(pmtp);
                pm.setName(pmnm);
                fn.addParam(pm);
            }
        }

        // 搞定
        return fn;
    }

}
