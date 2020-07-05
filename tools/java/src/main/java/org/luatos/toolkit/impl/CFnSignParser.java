package org.luatos.toolkit.impl;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.luatos.toolkit.api.FnSignParser;
import org.luatos.toolkit.bean.FnLang;
import org.luatos.toolkit.bean.FnParam;
import org.luatos.toolkit.bean.FnReturn;
import org.luatos.toolkit.bean.FnSign;
import org.nutz.lang.Lang;
import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class CFnSignParser implements FnSignParser {

    private static String _r0 = "^\\s*((((static|local|inline)\\s+)*))?\\s*(\\w+(\\s*[*])?)\\s*(\\w+)\\s*\\(([^)]*)\\).*$";
    private static Pattern PT = Regex.getPattern(_r0);

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
        String retp = m.group(5);
        String name = m.group(7);
        String params = m.group(8);

        // 准备返回
        FnSign fn = new FnSign();
        fn.setRawText(block);
        fn.setLang(FnLang.C);

        fn.setModifier(mod);
        fn.setName(name);

        fn.addReturn(new FnReturn(retp));

        // 分析参数
        String[] ss = Strings.splitIgnoreBlank(params);
        if (ss.length == 0) {
            fn.setParams(new ArrayList<>(0));
        }
        // 循环判断参数
        else {
            for (String s : ss) {
                String[] mm = Strings.splitIgnoreBlank(s, "\\s+");
                String md = null;
                String tp = null;
                String nm = null;
                // 只有一个
                if (1 == mm.length) {
                    nm = mm[0];
                }
                // 两个的话，那么前面一个是类型
                else if (2 == mm.length) {
                    tp = mm[0];
                    nm = mm[1];
                }
                // 超过两个，第一个是类型，最后一个是名称
                else {
                    int last = mm.length - 1;
                    md = mm[0];
                    String[] tps = Arrays.copyOfRange(mm, 1, last);
                    tp = Strings.join(" ", tps);
                    nm = mm[last];
                }
                // 弄一下指针
                if (nm.startsWith("*")) {
                    nm = nm.substring(1).trim();
                    tp += "*";
                }
                // void 类型
                if (null == tp && "void".equals(nm)) {
                    tp = nm;
                    nm = null;
                }

                // 生成参数对象
                FnParam pm = new FnParam();
                pm.setModifier(md);
                pm.setType(tp);
                pm.setName(nm);
                fn.addParam(pm);
            }
        }

        // 搞定
        return fn;
    }

}
