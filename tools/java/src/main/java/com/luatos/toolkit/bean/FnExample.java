package com.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;

import org.nutz.lang.Strings;

import com.luatos.toolkit.Luats;

public class FnExample {

    private List<String> summary;

    private List<String> code;

    public boolean hasSummary() {
        return null != summary && !summary.isEmpty();
    }

    public List<String> getSummary() {
        return summary;
    }

    public void setSummary(List<String> summary) {
        this.summary = summary;
    }

    public void appendSummary(String summary) {
        if (null == this.summary) {
            this.summary = new LinkedList<>();
        }
        this.summary.add(summary);
    }

    public boolean hasCode() {
        return null != code && !code.isEmpty();
    }

    public List<String> getCode() {
        return code;
    }

    public void setCode(List<String> code) {
        this.code = code;
    }

    public void appendCode(String code) {
        if (null == this.code) {
            this.code = new LinkedList<>();
        }
        this.code.add(code);
    }

    public String toString() {
        String str = "";
        if (this.hasSummary()) {
            str += Strings.join("\n--", this.summary) + "\n";
        }
        str += Strings.join("\n", code);
        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnExample) {
            FnExample fe = (FnExample) o;
            if (!Luats.isSameList(this.summary, fe.summary))
                return false;

            if (!Luats.isSameList(this.code, fe.code))
                return false;

            return true;
        }
        return false;
    }

}
