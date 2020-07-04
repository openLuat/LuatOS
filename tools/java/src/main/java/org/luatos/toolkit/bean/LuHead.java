package org.luatos.toolkit.bean;

import org.luatos.toolkit.Luats;
import org.nutz.lang.Strings;
import org.nutz.lang.util.NutMap;

public class LuHead {

    private String title;

    private String path;

    private String module;

    private String summary;

    private String version;

    private String date;

    public String getTitle() {
        return title;
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

    public String getModule() {
        return module;
    }

    public void setModule(String module) {
        this.module = module;
    }

    public String getSummary() {
        return summary;
    }

    public void setSummary(String summary) {
        this.summary = summary;
    }

    public String getVersion() {
        return version;
    }

    public void setVersion(String version) {
        this.version = version;
    }

    public String getDate() {
        return date;
    }

    public void setDate(String date) {
        this.date = date;
    }

    public boolean equals(Object o) {
        if (o instanceof LuHead) {
            LuHead he = (LuHead) o;
            if (!Luats.isSame(title, he.title))
                return false;
            if (!Luats.isSame(path, he.path))
                return false;
            if (!Luats.isSame(module, he.module))
                return false;
            if (!Luats.isSame(summary, he.summary))
                return false;
            if (!Luats.isSame(version, he.version))
                return false;
            if (!Luats.isSame(date, he.date))
                return false;

            return true;
        }
        return false;
    }

    public NutMap toMap() {
        NutMap re = new NutMap();

        if (!Strings.isBlank(title))
            re.put("title", title);

        if (!Strings.isBlank(path))
            re.put("path", path);

        if (!Strings.isBlank(module))
            re.put("module", module);

        if (!Strings.isBlank(summary))
            re.put("summary", summary);

        if (!Strings.isBlank(version))
            re.put("version", version);

        if (!Strings.isBlank(date))
            re.put("date", date);
        return re;
    }

    public String toString() {
        String s = "";
        if (!Strings.isBlank(title))
            s += "@title " + title + "\n";

        if (!Strings.isBlank(path))
            s += "@path " + path + "\n";

        if (!Strings.isBlank(summary))
            s += "@summary " + summary + "\n";

        if (!Strings.isBlank(module))
            s += "@module " + module + "\n";

        if (!Strings.isBlank(summary))
            s += "@summary " + summary + "\n";

        if (!Strings.isBlank(version))
            s += "@version " + version + "\n";

        if (!Strings.isBlank(date))
            s += "@date " + date;
        return s;
    }

    public void mergeWith(LuHead head) {
        if (null == head)
            return;

        if (!Strings.isBlank(head.title))
            this.title = head.title;

        if (!Strings.isBlank(head.path))
            this.path = head.path;

        if (!Strings.isBlank(head.summary))
            this.summary = head.summary;

        if (!Strings.isBlank(head.module))
            this.module = head.module;

        if (!Strings.isBlank(head.summary))
            this.summary = head.summary;

        if (!Strings.isBlank(head.version))
            this.version = head.version;

        if (!Strings.isBlank(head.date))
            this.date = head.date;
    }

}
