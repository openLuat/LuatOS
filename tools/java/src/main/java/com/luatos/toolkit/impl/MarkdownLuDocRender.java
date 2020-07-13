package com.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.util.List;
import java.util.Map;

import org.nutz.lang.Lang;
import org.nutz.lang.Streams;
import org.nutz.lang.Strings;
import org.nutz.lang.util.NutMap;

import com.luatos.toolkit.LuatRenderingSetup;
import com.luatos.toolkit.api.LuDocRender;
import com.luatos.toolkit.bean.FnExample;
import com.luatos.toolkit.bean.FnParam;
import com.luatos.toolkit.bean.FnReturn;
import com.luatos.toolkit.bean.FnSign;
import com.luatos.toolkit.bean.LuDocument;

public class MarkdownLuDocRender implements LuDocRender {

    @Override
    public boolean render(LuDocument doc, OutputStream ops, LuatRenderingSetup setup) {
        BufferedWriter br = Streams.buffw(new OutputStreamWriter(ops));

        try {
            return safeWrite(doc, br, setup);
        }
        catch (IOException e) {
            throw Lang.wrapThrow(e);
        }
        finally {
            Streams.safeFlush(br);
        }
    }

    private void wlnf(BufferedWriter br, String fmt, Object... args) throws IOException {
        if (null != fmt) {
            if (null == args || args.length == 0) {
                br.write(fmt);
            } else {
                String str = String.format(fmt, args);
                br.write(str);
            }
            br.write("\n");
        }
    }

    private static final String HR = Strings.dup('-', 50);

    private boolean safeWrite(LuDocument doc, BufferedWriter br, LuatRenderingSetup setup)
            throws IOException {
        // 书写头部
        if (doc.hasHead()) {
            NutMap map = doc.getHead().toMap();
            wlnf(br, "---");
            for (Map.Entry<String, Object> en : map.entrySet()) {
                wlnf(br, "%s: %s", en.getKey(), en.getValue());
            }
            wlnf(br, "---\n");
        }

        // 木有内容哦 ...
        List<FnSign> funcs = doc.fetchFunctions(setup);
        if (funcs.isEmpty())
            return false;

        // 每个函数一节
        for (FnSign fn : funcs) {
            // 输出标题
            wlnf(br, HR);
            wlnf(br, "# %s\n", fn.getName());

            // 输出函数原型
            wlnf(br, "```%s", fn.getLangName());
            wlnf(br, fn.toSignature());
            wlnf(br, "```\n");

            // 摘要
            if (fn.hasSummary()) {
                wlnf(br, fn.getSummary());
            }

            // 标题二（参数）
            wlnf(br, "\n## 参数表\n");
            if (fn.hasParams()) {
                wlnf(br, "Name | Type | Description");
                wlnf(br, "-----|------|--------------");
                for (FnParam fp : fn.getParams()) {
                    String brief = tidyBrief(fp.getComment());
                    wlnf(br, "`%s`|`%s`| %s", fp.getName(), fp.getType(), brief);
                }
            } else {
                wlnf(br, "> 无参数");
            }

            // 标题二（返回值）
            wlnf(br, "\n## 返回值\n");
            if (fn.hasReturns() && !fn.isReturnMatch(0, "void")) {
                wlnf(br, "No. | Type | Description");
                wlnf(br, "----|------|--------------");
                int x = 0;
                for (FnReturn fr : fn.getReturns()) {
                    String brief = tidyBrief(fr.getComment());
                    wlnf(br, "%d |`%s`| %s", ++x, fr.getType(), brief);
                }
            } else {
                wlnf(br, "> *无返回值*");
            }

            // 标题二（例子）
            if (fn.hasExamples()) {
                wlnf(br, "\n## 调用示例\n");
                wlnf(br, "```%s", fn.getLangName());
                for (FnExample fe : fn.getExamples()) {
                    wlnf(br, "-- %s", Strings.join("\n-- ", fe.getSummary()));
                    wlnf(br, Strings.join("\n", fe.getCode()));
                }
                wlnf(br, "```");
            }

            // 标题二（参考函数）
            if (fn.hasRefer()) {
                wlnf(br, "\n## C API");
                wlnf(br, "\n```c");
                wlnf(br, fn.getRefer().toSignature());
                wlnf(br, "```");
            }

            // 最后结束来个空行
            wlnf(br, "\n");
        }

        return true;
    }

    private String tidyBrief(String brief) {
        if (Strings.isBlank(brief)) {
            brief = "*无*";
        } else {
            brief = brief.replaceAll("\r?\n", " ");
        }
        return brief;
    }

}
