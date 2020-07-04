package org.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.util.Map;

import org.luatos.toolkit.api.LuDocRender;
import org.luatos.toolkit.bean.FnSign;
import org.luatos.toolkit.bean.LuDocument;
import org.nutz.lang.Lang;
import org.nutz.lang.Streams;
import org.nutz.lang.util.NutMap;

public class MarkdownLuDocRender implements LuDocRender {

    @Override
    public void render(LuDocument doc, OutputStream ops) {
        BufferedWriter br = Streams.buffw(new OutputStreamWriter(ops));

        try {
            safeWrite(doc, br);
        }
        catch (IOException e) {
            throw Lang.wrapThrow(e);
        }
        finally {
            Streams.safeClose(br);
        }
    }

    private void wlnf(BufferedWriter br, String fmt, Object... args) throws IOException {
        String str = String.format(fmt, args);
        br.write(str + "\n");
    }

    private void safeWrite(LuDocument doc, BufferedWriter br) throws IOException {
        // 书写头部
        if (doc.hasHead()) {
            NutMap map = doc.getHead().toMap();
            wlnf(br, "---");
            for (Map.Entry<String, Object> en : map.entrySet()) {
                wlnf(br, "%s: %s", en.getKey(), en.getValue());
            }
            wlnf(br, "---");
        }

        // 木有内容哦 ...
        if (!doc.hasFunctions())
            return;

        // 每个函数一节
        for (FnSign fn : doc.getFunctions()) {
            // 输出标题
            wlnf(br, "\n# %s\n", fn.getName());

            // 摘要
            wlnf(br, fn.getSummary());

            // 标题二（参数）
            wlnf(br, "## 参数表");
            if (fn.hasParams()) {

            }

            // 标题二（返回值）
            wlnf(br, "## 返回值");
            if (fn.hasReturns()) {}

            // 标题二（例子）
            if (fn.hasExamples()) {
                wlnf(br, "## 调用示例");
            }

            // 标题二（参考函数）
            if (fn.hasRefer()) {
                wlnf(br, "## C API");
            }
        }

    }

}
