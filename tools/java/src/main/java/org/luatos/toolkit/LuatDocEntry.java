package org.luatos.toolkit;

import org.nutz.lang.Files;
import org.nutz.lang.Strings;

public class LuatDocEntry {

    private String title;

    private String path;

    /**
     * 从 workdir+path 之后的路径开始算，一定不是 "/" 开头
     */
    private String[] prefix;

    private String[] suffix;

    /**
     * 输数模板：占位符：
     * 
     * <ul>
     * <li><code>${name}</code>: path 所在目录名
     * </ul>
     */
    private String out;

    private boolean deep;

    public String getTitle() {
        return title;
    }

    public String getTitle2() {
        if (!Strings.isBlank(title)) {
            return this.title;
        }
        return Strings.sBlank(Files.getName(path), "NoTitle");
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getPath() {
        return path;
    }

    public void setPath(String path) {
        this.path = path;
    }

    public String[] getPrefix() {
        return prefix;
    }

    public void setPrefix(String[] prefix) {
        this.prefix = prefix;
    }

    public String[] getSuffix() {
        return suffix;
    }

    public void setSuffix(String[] suffix) {
        this.suffix = suffix;
    }

    public boolean isMatch(String rph) {
        // 先看后缀
        if (hasSuffix()) {
            boolean found = false;
            for (String sufx : this.suffix) {
                if (rph.endsWith(sufx)) {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }

        // 再看前缀
        if (hasPrefix()) {
            boolean found = false;
            for (String prfx : this.prefix) {
                if (rph.startsWith(prfx)) {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }

        // 那么就过咯
        return true;
    }

    public boolean hasPrefix() {
        return null != this.prefix && this.prefix.length > 0;
    }

    public boolean hasSuffix() {
        return null != this.suffix && this.suffix.length > 0;
    }

    public String getOut() {
        return out;
    }

    public void setOut(String out) {
        this.out = out;
    }

    public boolean isDeep() {
        return deep;
    }

    public void setDeep(boolean deep) {
        this.deep = deep;
    }

    public String toString() {
        String s = String.format("# %s->%s", this.getTitle2(), this.path);
        if (this.hasPrefix()) {
            s += "\n#  prefix: " + Strings.join(", ", this.prefix);
        }
        if (this.hasSuffix()) {
            s += "\n#  suffix: " + Strings.join(", ", this.suffix);
        }
        s += "\n#    deep: " + this.deep;
        s += "\n#     out: " + this.out;
        s += "\n#";
        return s;
    }

}
