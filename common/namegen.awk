BEGIN {
    for (i = 32; i < 127; i++) ORD[sprintf("%c", i)] = i
    M = 4294967296
}

NR == 1 { nd = split($0, D, " ") }
NR == 2 { nt = split($0, T, " ") }

function fail(why) {
    print why
    exit 2
}

function u16(a, i) { return a[i] * 256 + a[i+1] }
function u32(a, i) { return ((a[i] * 256 + a[i+1]) * 256 + a[i+2]) * 256 + a[i+3] }
function pad(n) { return int((n + 3) / 4) * 4 }

function set32(a, i, v) {
    a[i] = int(v / 16777216) % 256; a[i+1] = int(v / 65536) % 256
    a[i+2] = int(v / 256) % 256;    a[i+3] = v % 256
}

function slice(a, i, n,    s, k) {
    s = ""
    for (k = 0; k < n; k++) s = s " " a[i+k]
    return s
}

function count(v,    t) { return split(v, t, " ") }

# Bytes per character of a name record encoding: 2 = UTF-16BE, 1 = ASCII-compatible, 0 = unknown.
function width(p, e) {
    if (p == 0) return 2
    if (p == 3 && (e == 0 || e == 1 || e == 10)) return 2
    if (p == 1 && e == 0) return 1
    return 0
}

function encode(s, w,    v, k, c) {
    v = ""
    for (k = 1; k <= length(s); k++) {
        c = substr(s, k, 1)
        if (!(c in ORD)) fail("family name must be printable ASCII")
        v = v (w == 2 ? " 0 " : " ") ORD[c]
    }
    return v
}

function put16(v) { OB[++ob] = int(v / 256) % 256; OB[++ob] = v % 256 }

function putv(v,    t, n, k) {
    n = split(v, t, " ")
    for (k = 1; k <= n; k++) OB[++ob] = t[k]
}

function store(v) {
    if (!(v in POOL)) { POOL[v] = plen; pool = pool v; plen += count(v) }
    return POOL[v]
}

function sum(a, n,    s, k) {
    s = 0
    for (k = 1; k + 3 <= n; k += 4) s = (s + u32(a, k)) % M
    return s
}

function emit(a, n, file,    k, s) {
    s = ""
    for (k = 1; k <= n; k++) {
        s = s sprintf("\\%03o", a[k])
        if (k % 64 == 0) { print s > file; s = "" }
    }
    if (s != "") print s > file
    close(file)
}

END {
    if (nd < 12) fail("truncated table directory")
    ntab = u16(D, 5)
    if (nd != 12 + ntab * 16) fail("truncated table directory")
    ni = 0; hi = 0
    for (k = 0; k < ntab; k++) {
        b = 13 + k * 16
        tag = sprintf("%c%c%c%c", D[b], D[b+1], D[b+2], D[b+3])
        if (tag == "name") ni = b
        if (tag == "head") hi = b
    }
    if (!ni) fail("no name table")
    noff = u32(D, ni + 8); nlen = u32(D, ni + 12)
    if (noff < nd) fail("name table overlaps table directory")
    if (nt != nlen || nt < 6) fail("truncated name table")

    fmt = u16(T, 1); cnt = u16(T, 3); so = u16(T, 5)
    if (fmt > 1) fail("unsupported name table format " fmt)
    hdr = 6 + cnt * 12
    ltc = 0
    if (fmt == 1) {
        if (hdr + 2 > nt) fail("truncated name table")
        ltc = u16(T, hdr + 1)
        hdr += 2 + ltc * 4
    }
    if (hdr > nt || so > nt) fail("truncated name table")
    for (k = 0; k < cnt; k++) {
        b = 7 + k * 12
        RP[k] = u16(T, b); RE[k] = u16(T, b + 2); RL[k] = u16(T, b + 4); RN[k] = u16(T, b + 6)
        len = u16(T, b + 8); off = u16(T, b + 10)
        if (so + off + len > nt) fail("name record out of range")
        RV[k] = slice(T, so + off + 1, len)
        key = RP[k] SUBSEP RE[k] SUBSEP RL[k]
        if (RN[k] == 2) S2[key] = RV[k]
        if (RN[k] == 17) S17[key] = RV[k]
    }
    for (k = 0; k < ltc; k++) {
        b = 7 + cnt * 12 + 2 + k * 4
        len = u16(T, b); off = u16(T, b + 2)
        if (so + off + len > nt) fail("language tag out of range")
        LV[k] = slice(T, so + off + 1, len)
    }

    m = 0
    for (k = 0; k < cnt; k++) {
        v = RV[k]
        if (RN[k] == 1 || RN[k] == 4 || RN[k] == 16 || RN[k] == 21) {
            w = width(RP[k], RE[k])
            if (!w) continue
            v = encode(NAME, w)
            if (RN[k] == 4) {
                key = RP[k] SUBSEP RE[k] SUBSEP RL[k]
                s = (key in S17) ? S17[key] : S2[key]
                if (s != "" && s != encode("Regular", w)) v = v encode(" ", w) s
            }
        }
        NP[m] = RP[k]; NE[m] = RE[k]; NL[m] = RL[k]; NN[m] = RN[k]; NV[m] = v
        m++
    }

    ob = 0; pool = ""; plen = 0
    put16(fmt); put16(m); put16(6 + m * 12 + (fmt == 1 ? 2 + ltc * 4 : 0))
    for (k = 0; k < m; k++) {
        put16(NP[k]); put16(NE[k]); put16(NL[k]); put16(NN[k])
        put16(count(NV[k])); put16(store(NV[k]))
    }
    if (fmt == 1) {
        put16(ltc)
        for (k = 0; k < ltc; k++) { put16(count(LV[k])); put16(store(LV[k])) }
    }
    if (plen > 65535) fail("name storage too large")
    putv(pool)
    nnew = ob
    while (ob % 4) OB[++ob] = 0

    oend = noff + pad(nlen)
    delta = ob - pad(nlen)
    for (k = 1; k <= nd; k++) ND[k] = D[k]
    for (k = 0; k < ntab; k++) {
        b = 13 + k * 16
        if (b == ni) continue
        off = u32(D, b + 8)
        if (off >= noff && off < oend) fail("table overlaps name table")
        if (off < noff && off + u32(D, b + 12) > noff) fail("table overlaps name table")
        if (off > noff) set32(ND, b + 8, off + delta)
    }
    set32(ND, ni + 4, sum(OB, ob))
    set32(ND, ni + 12, nnew)

    total = sum(ND, nd)
    for (k = 0; k < ntab; k++) total = (total + u32(ND, 17 + k * 16)) % M
    set32(A, 1, ((2981146554 - total) % M + M) % M)

    emit(ND, nd, DIR_OUT)
    emit(OB, ob, NAME_OUT)
    printf "%d %d %d %d %s\n", noff, oend, hi ? u32(ND, hi + 8) : -1, delta, \
        sprintf("\\%03o\\%03o\\%03o\\%03o", A[1], A[2], A[3], A[4])
}
