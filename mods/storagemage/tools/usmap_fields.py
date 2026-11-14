"""Dump fields of structs/classes and values of enums from an unversioned, uncompressed .usmap.
python usmap_fields.py <usmap> Name1 Name2 ...   (prefix ~ for substring match)"""
import struct, sys
TYPES = ["Byte","Bool","Int","Float","Object","Name","Delegate","Double","Array","Struct","Str","Text","Interface",
 "MulticastDelegate","WeakObject","LazyObject","AssetObject","SoftObject","UInt64","UInt32","UInt16","Int64","Int16",
 "Int8","Map","Set","Enum","FieldPath","Optional","Utf8Str","AnsiStr"]
d = open(sys.argv[1], "rb").read()
_m, ver = struct.unpack_from("<HB", d, 0); o = 3
if ver >= 1: o += 4
o += 1; csize, _ = struct.unpack_from("<II", d, o); o += 8
b = d[o:o+csize]; p = [0]
def t(f):
    v = struct.unpack_from("<"+f, b, p[0]); p[0] += struct.calcsize("<"+f); return v[0]
names = []
for _ in range(t("i")):
    n = t("H") if ver >= 2 else t("B"); names.append(b[p[0]:p[0]+n].decode("utf-8","replace")); p[0] += n
N = lambda i: "None" if i == 0xFFFFFFFF or i < 0 else names[i]
enums = {}
for _ in range(t("i")):
    en = N(t("I")); cnt = t("H") if ver >= 3 else t("B"); vals = []
    for _ in range(cnt):
        if ver >= 4: v = t("q"); vals.append((v, N(t("I"))))
        else: vals.append((len(vals), N(t("I"))))
    enums[en] = vals
def typ():
    k = TYPES[t("B")]
    if k == "Enum": inner = typ(); return "Enum<%s>" % N(t("I"))
    if k == "Struct": return "Struct<%s>" % N(t("I"))
    if k in ("Array","Set","Optional"): return "%s<%s>" % (k, typ())
    if k == "Map": a = typ(); return "Map<%s,%s>" % (a, typ())
    return k
structs = {}
for _ in range(t("i")):
    sn = N(t("I")); sup = N(t("I")); _pc = t("H"); spc = t("H"); props = []
    for _ in range(spc):
        _idx = t("H"); dim = t("B"); pn = N(t("I")); props.append((pn, typ(), dim))
    structs[sn] = (sup, props)
for q in sys.argv[2:]:
    keys = [k for k in list(structs) + list(enums) if (q[1:].lower() in k.lower() if q[0] == "~" else k == q)]
    if q[0] == "~": print("~%s: %s" % (q[1:], ", ".join(sorted(set(keys))))); continue
    for k in keys:
        if k in enums: print("enum %s: %s" % (k, ", ".join("%s=%d" % (n, v) for v, n in enums[k])))
        if k in structs:
            sup, props = structs[k]; print("%s : %s" % (k, sup))
            for pn, ty, dim in props: print("   %s %s%s" % (ty, pn, "[%d]" % dim if dim > 1 else ""))
    if not keys: print("?? " + q)
