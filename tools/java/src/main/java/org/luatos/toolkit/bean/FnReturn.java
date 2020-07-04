package org.luatos.toolkit.bean;

import org.luatos.toolkit.Luats;
import org.nutz.lang.Strings;

public class FnReturn {

    protected String type;

    protected String comment;

    public FnReturn() {}

    public FnReturn(String type) {
        this.type = type;
    }

    public FnReturn(String type, String comment) {
        this.type = type;
        this.comment = comment;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getComment() {
        return comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }

    public String toString() {
        String str = type;
        if (!Strings.isBlank(comment)) {
            str += "/* " + comment + " */";
        }
        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnReturn) {
            FnReturn fr = (FnReturn) o;
            if (!Luats.isSame(this.type, fr.type))
                return false;

            if (!Luats.isSame(this.comment, fr.comment))
                return false;

            return true;
        }
        return false;
    }

}
