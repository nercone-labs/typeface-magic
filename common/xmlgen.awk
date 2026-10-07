BEGIN {
    nr = split(ROLES, rr, ";")
    for (i = 1; i <= nr; i++) {
        if (rr[i] == "") continue
        split(rr[i], f, "|")
        r = f[1]
        HAVE[r] = 1
        UP[r] = f[2];  UV[r] = f[3] + 0; UMIN[r] = f[4] + 0; UMAX[r] = f[5] + 0
        IT[r] = f[6];  IV[r] = f[7] + 0; IMIN[r] = f[8] + 0; IMAX[r] = f[9] + 0
        AXS[r] = f[10]
    }
    np = 0
    addpat("sans", PAT_SANS)
    addpat("serif", PAT_SERIF)
    addpat("mono", PAT_MONO)
    nfp = 0
    addfpat("mono", FPAT_MONO)
    addfpat("serif", FPAT_SERIF)
    addfpat("sans", FPAT_SANS)
    ncl = split(CJK, CL, " ")
    IND = "        "
    ERR = 0
}

function addpat(role, list,    k, a, i, p) {
    k = split(list, a, " ")
    for (i = 1; i <= k; i++) {
        if (a[i] == "") continue
        p = a[i]
        gsub(/\./, "[.]", p)
        gsub(/\*/, ".*", p)
        np++
        PR[np] = role
        PP[np] = "^" p "$"
    }
}

function addfpat(role, list,    k, a, i, p) {
    k = split(list, a, " ")
    for (i = 1; i <= k; i++) {
        if (a[i] == "") continue
        p = a[i]
        gsub(/\./, "[.]", p)
        gsub(/\*/, "[^<> \t\r\n]*", p)
        nfp++
        FR[nfp] = role
        FP[nfp] = "[> \t\r\n]" p "[.]([Tt][Tt][FfCc]|[Oo][Tt][Ff])[ \t\r\n]*<"
    }
}

function classify(name, blk,    i) {
    for (i = 1; i <= np; i++)
        if (name ~ PP[i]) return PR[i]
    for (i = 1; i <= nfp; i++)
        if (blk ~ FP[i]) return FR[i]
    return ""
}

function attr(tag, name,    re, v) {
    re = "[ \t\r\n]" name "[ \t\r\n]*=[ \t\r\n]*\"[^\"]*\""
    if (match(tag, re)) {
        v = substr(tag, RSTART, RLENGTH)
        sub(/^[^"]*"/, "", v)
        sub(/"$/, "", v)
        return v
    }
    re = "[ \t\r\n]" name "[ \t\r\n]*=[ \t\r\n]*'[^']*'"
    if (match(tag, re)) {
        v = substr(tag, RSTART, RLENGTH)
        sub(/^[^']*'/, "", v)
        sub(/'$/, "", v)
        return v
    }
    return ""
}

function axline(tag, val) {
    return "<axis tag=\"" tag "\" stylevalue=\"" val "\"/>"
}

function extra(r,    k, a, i, kv, s) {
    s = ""
    if (AXS[r] == "") return ""
    k = split(AXS[r], a, ",")
    for (i = 1; i <= k; i++) {
        split(a[i], kv, "=")
        if (kv[1] != "" && kv[2] != "" && kv[1] != "wght" && kv[1] != "ital")
            s = s axline(kv[1], kv[2])
    }
    return s
}

function fontel(w, style, file, sa, fb, inner,    s) {
    s = "<font weight=\"" w "\" style=\"" style "\""
    if (sa) s = s " supportedAxes=\"wght\""
    if (fb != "") s = s " fallbackFor=\"" fb "\""
    return IND s ">" file inner "</font>\n"
}

function genfile(r, file, isvar, wmin, wmax, style, fb, sa,    out, w, v) {
    out = ""
    if (file == "") return ""
    if (isvar && sa) {
        out = fontel(400, style, file, 1, fb, extra(r))
    } else if (isvar) {
        for (w = 100; w <= 900; w += 100) {
            v = w
            if (v < wmin) v = wmin
            if (v > wmax) v = wmax
            out = out fontel(w, style, file, 0, fb, axline("wght", v) extra(r))
        }
    } else {
        out = fontel(400, style, file, 0, fb, "")
    }
    return out
}

function genfonts(r, fb,    sa) {
    sa = SA
    if (!UV[r]) sa = 0
    if (IT[r] != "" && !IV[r]) sa = 0
    return genfile(r, UP[r], UV[r], UMIN[r], UMAX[r], "normal", fb, sa) \
           genfile(r, IT[r], IV[r], IMIN[r], IMAX[r], "italic", fb, sa)
}

function report(s) {
    if (REPORT != "") print s >> REPORT
}

function process(blk, tag, islist, selfclose,    name, role, lang, L, i, ins) {
    name = attr(tag, "name")
    if (name != "") {
        role = classify(name, blk)
        if (role == "" || !HAVE[role] || selfclose) return blk
        report("replace " name " -> " role)
        if (islist)
            return tag "\n    <family>\n" genfonts(role, "") "    </family>\n</family-list>"
        return tag "\n" genfonts(role, "") "    </family>"
    }
    if (MODE != "main" || selfclose || islist || !HAVE["sans"]) return blk
    lang = attr(tag, "lang")
    if (lang == "") return blk
    split(lang, L, ",")
    for (i = 1; i <= ncl; i++) {
        if (CL[i] == "" || L[1] != CL[i] || INS[CL[i]]) continue
        INS[CL[i]] = 1
        ins = "<family lang=\"" lang "\">\n" genfonts("sans", "")
        if (HAVE["serif"]) ins = ins genfonts("serif", "serif")
        if (HAVE["mono"]) ins = ins genfonts("mono", "monospace")
        ins = ins "    </family>\n    "
        report("prepend fallback lang=" lang)
        return ins blk
    }
    return blk
}

{ S = S $0 "\n" }

END {
    out = ""
    rest = S
    while (1) {
        im = match(rest, "<family(-list)?[ \t\r\n>/]")
        if (im == 0) break
        ic = index(rest, "<!--")
        if (ic > 0 && ic < im) {
            e = index(substr(rest, ic), "-->")
            if (e == 0) { ERR = 1; break }
            e = ic + e + 1
            out = out substr(rest, 1, e)
            rest = substr(rest, e + 1)
            continue
        }
        out = out substr(rest, 1, im - 1)
        rest = substr(rest, im)
        islist = (substr(rest, 1, 12) == "<family-list")
        gt = index(rest, ">")
        if (gt == 0) { ERR = 1; break }
        tag = substr(rest, 1, gt)
        selfclose = (substr(tag, gt - 1, 1) == "/")
        if (selfclose) {
            blk = tag
        } else {
            endtag = islist ? "</family-list>" : "</family>"
            e = index(rest, endtag)
            if (e == 0) { ERR = 1; break }
            blk = substr(rest, 1, e + length(endtag) - 1)
        }
        rest = substr(rest, length(blk) + 1)
        out = out process(blk, tag, islist, selfclose)
    }
    if (ERR) exit 2
    out = out rest
    printf "%s<!-- %s -->\n", out, MARK
}
