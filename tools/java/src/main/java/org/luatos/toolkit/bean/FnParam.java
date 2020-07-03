package org.luatos.toolkit.bean;

import org.luatos.toolkit.Luats;
import org.nutz.lang.Strings;

public class FnParam {

    private String type;

    private String name;

    private String comment;

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        if (Strings.isBlank(name)) {
            this.name = null;
        } else {
            this.name = name;
        }
    }

    public String getComment() {
        return comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }

    public String toString() {
        String str = type;
        if (str.endsWith(" *")) {
            str += name;
        } else {
            str += " " + name;
        }
        if (!Strings.isBlank(comment)) {
            str += "/* " + comment + " */";
        }
        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnParam) {
            FnParam fp = (FnParam) o;
            if (!Luats.isSame(this.type, fp.type))
                return false;

            if (!Luats.isSame(this.name, fp.name))
                return false;

            if (!Luats.isSame(this.comment, fp.comment))
                return false;

            return true;
        }
        return false;
    }

}
