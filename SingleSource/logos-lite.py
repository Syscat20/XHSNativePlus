#!/usr/bin/env python3
"""Minimal Logos-to-ObjC++ translator for SingleSource/XHSNative.xm when Theos logos.pl is absent."""
import re
import sys
from pathlib import Path


def split_top_level_args(text: str):
    args = []
    depth = 0
    cur = []
    in_str = None
    esc = False
    for ch in text:
        if esc:
            cur.append(ch)
            esc = False
            continue
        if in_str:
            cur.append(ch)
            if ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
            continue
        if ch in ('"', "'"):
            in_str = ch
            cur.append(ch)
        elif ch in ("(", "[", "{", "<"):
            depth += 1
            cur.append(ch)
        elif ch in (")", "]", "}", ">"):
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur or args:
        args.append("".join(cur).strip())
    return args


def parse_method_sig(sig_line: str):
    # e.g. - (void)setStandardAppearance:(UITabBarAppearance *)appearance
    m = re.match(r"^\s*([+-])\s*\(([^()]+(?:\([^)]*\)[^()]*)*)\)\s*(.+?)\s*$", sig_line)
    if not m:
        raise ValueError(f"Cannot parse method signature: {sig_line}")
    kind = m.group(1)  # '+' or '-'
    ret_type = m.group(2).strip()
    rest = m.group(3).strip()

    # Check if unary selector (no ':')
    if ":" not in rest:
        sel = rest.strip()
        return kind, ret_type, sel, []

    # Selector with parameters: label:(Type)name ...
    params = []
    sel_parts = []
    i = 0
    n = len(rest)
    while i < n:
        while i < n and rest[i].isspace():
            i += 1
        if i >= n:
            break
        colon = rest.find(":", i)
        if colon == -1:
            break
        label = rest[i:colon].strip()
        sel_parts.append(label + ":")
        i = colon + 1
        while i < n and rest[i].isspace():
            i += 1
        if i >= n or rest[i] != "(":
            raise ValueError(f"Expected '(' in method signature: {sig_line}")
        depth = 1
        j = i + 1
        while j < n and depth > 0:
            if rest[j] == "(":
                depth += 1
            elif rest[j] == ")":
                depth -= 1
            j += 1
        ptype = rest[i + 1 : j - 1].strip()
        i = j
        while i < n and rest[i].isspace():
            i += 1
        k = i
        while k < n and (rest[k].isalnum() or rest[k] == "_"):
            k += 1
        pname = rest[i:k]
        i = k
        params.append((ptype, pname))
    return kind, ret_type, "".join(sel_parts), params


def objc_type_encoding_expr(ctype: str) -> str:
    t = " ".join(ctype.split())
    if t == "void":
        return '"v"'
    if t in ("BOOL", "bool"):
        return '"B"'
    if t == "NSInteger":
        return '@encode(NSInteger)'
    if t == "NSUInteger":
        return '@encode(NSUInteger)'
    if t == "CGFloat":
        return '@encode(CGFloat)'
    if t == "double":
        return '"d"'
    if t == "UIEdgeInsets":
        return '@encode(UIEdgeInsets)'
    if t == "CGRect":
        return '@encode(CGRect)'
    if t == "CGPoint":
        return '@encode(CGPoint)'
    if t == "CGSize":
        return '@encode(CGSize)'
    if "*" in t or t == "id" or t.startswith("id<") or t.endswith("Class"):
        return '"@"'
    return f'@encode({t})'


def replace_percent_c(text: str) -> str:
    return re.sub(r"%c\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", r'_logos_cls_\1', text)


def replace_orig(body: str, is_subclass: bool, super_cls_var: str, orig_var: str,
                 ret_type: str, sel: str, params, kind: str) -> str:
    param_names = [p[1] for p in params]
    self_expr = f"({ 'Class' if kind == '+' else 'id' })self"
    def make_call(arg_list):
        if is_subclass:
            # Call super implementation via class_getMethodImplementation(superclass, sel)
            ptypes = ", ".join(["id", "SEL"] + [p[0] for p in params])
            args = ", ".join(["self", "_cmd"] + arg_list)
            return f"(({ret_type} (*)({ptypes}))class_getMethodImplementation({super_cls_var}, @selector({sel})))({args})"
        else:
            args = ", ".join(["self", "_cmd"] + arg_list)
            return f"{orig_var}({args})"

    out = []
    i = 0
    n = len(body)
    while i < n:
        if body.startswith("%orig", i) and (i == 0 or not (body[i - 1].isalnum() or body[i - 1] == "_")):
            j = i + 5
            if j < n and body[j] == "(":
                depth = 1
                k = j + 1
                in_str = None
                esc = False
                while k < n and depth > 0:
                    ch = body[k]
                    if esc:
                        esc = False
                    elif in_str:
                        if ch == "\\":
                            esc = True
                        elif ch == in_str:
                            in_str = None
                    elif ch in ('"', "'"):
                        in_str = ch
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    k += 1
                inner = body[j + 1 : k - 1].strip()
                arg_list = split_top_level_args(inner) if inner else []
                out.append(make_call(arg_list))
                i = k
                continue
            elif j == n or not (body[j].isalnum() or body[j] == "_"):
                out.append(make_call(param_names))
                i = j
                continue
        out.append(body[i])
        i += 1
    return "".join(out)


def translate(src: str) -> str:
    lines = src.splitlines()
    preamble = []
    blocks = []
    ctor_lines = []

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m_hook = re.match(r"^\s*%hook\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
        m_sub = re.match(r"^\s*%subclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
        m_ctor = re.match(r"^\s*%ctor\s*\{\s*$", line)
        if m_hook or m_sub:
            is_sub = bool(m_sub)
            cls_name = m_sub.group(1) if is_sub else m_hook.group(1)
            super_name = m_sub.group(2) if is_sub else None
            block_lines = []
            i += 1
            while i < n and not re.match(r"^\s*%end\s*$", lines[i]):
                block_lines.append(lines[i])
                i += 1
            blocks.append((is_sub, cls_name, super_name, block_lines))
        elif m_ctor:
            depth = 1
            i += 1
            while i < n and depth > 0:
                l = lines[i]
                # rough brace count ignoring strings/comments (sufficient for XHSNative.xm)
                clean = re.sub(r"//.*", "", re.sub(r'"([^"\\]|\\.)*"', '""', l))
                depth += clean.count("{") - clean.count("}")
                if depth > 0:
                    ctor_lines.append(l)
                i += 1
            continue
        else:
            preamble.append(line)
        i += 1

    # Gather all class names referenced via %c(...) or %hook/%subclass
    all_classes = set()
    for is_sub, cls_name, super_name, _ in blocks:
        all_classes.add(cls_name)
        if super_name:
            all_classes.add(super_name)
    for cls_name in re.findall(r"%c\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", src):
        all_classes.add(cls_name)

    out = []
    out.append("// Generated by logos-lite.py")
    out.extend(preamble)
    out.append("#import <objc/runtime.h>")
    out.append("#import <objc/message.h>")
    out.append("")
    for cls in sorted(all_classes):
        out.append(f"@class {cls};")
        out.append(f"static Class _logos_cls_{cls};")
    out.append("")
    out.append("""static void _logos_register_hook(Class cls, SEL sel, IMP imp, IMP *orig) {
    if (!cls) return;
    for (Class cur = cls; cur; cur = class_getSuperclass(cur)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cur, &count);
        for (unsigned int i = 0; i < count; i++) {
            Method m = methods[i];
            if (method_getName(m) == sel) {
                if (cur == cls) {
                    *orig = method_setImplementation(m, imp);
                } else {
                    *orig = method_getImplementation(m);
                    class_addMethod(cls, sel, imp, method_getTypeEncoding(m));
                }
                free(methods);
                return;
            }
        }
        free(methods);
    }
}""")
    out.append("")

    init_registrations = []

    for is_sub, cls_name, super_name, blines in blocks:
        if is_sub:
            init_registrations.append(
                f'    _logos_cls_{cls_name} = objc_allocateClassPair(_logos_cls_{super_name} ?: objc_getClass("{super_name}"), "{cls_name}", 0);'
            )

        idx = 0
        mcount = 0
        pending_new = False
        while idx < len(blines):
            l = blines[idx]
            stripped = re.sub(r"//.*", "", l).strip()
            if not stripped:
                out.append(l)
                idx += 1
                continue
            if stripped == "%new":
                pending_new = True
                idx += 1
                continue
            m_prop = re.match(r"^%property\s*\(([^)]+)\)\s*(.+?[\s*])([A-Za-z_][A-Za-z0-9_]*)\s*;\s*$", stripped)
            if m_prop:
                attrs = m_prop.group(1)
                ptype = m_prop.group(2).strip()
                pname = m_prop.group(3).strip()
                assoc_policy = "OBJC_ASSOCIATION_COPY_NONATOMIC" if "copy" in attrs else "OBJC_ASSOCIATION_RETAIN_NONATOMIC"
                cap_name = pname[0].upper() + pname[1:]
                key_var = f"_logos_prop_key_{cls_name}_{pname}"
                getter_fn = f"_logos_prop_get_{cls_name}_{pname}"
                setter_fn = f"_logos_prop_set_{cls_name}_{pname}"
                out.append(f"static char {key_var};")
                out.append(f"static {ptype} {getter_fn}(id self, SEL _cmd) {{ (void)_cmd; return objc_getAssociatedObject(self, &{key_var}); }}")
                out.append(f"static void {setter_fn}(id self, SEL _cmd, {ptype} val) {{ (void)_cmd; objc_setAssociatedObject(self, &{key_var}, val, {assoc_policy}); }}")
                init_registrations.append(f'    class_addMethod(_logos_cls_{cls_name}, @selector({pname}), (IMP){getter_fn}, "@@:");')
                init_registrations.append(f'    class_addMethod(_logos_cls_{cls_name}, @selector(set{cap_name}:), (IMP){setter_fn}, "v@:@");')
                idx += 1
                continue

            if stripped.startswith("-") or stripped.startswith("+"):
                # Collect signature lines until '{'
                sig_lines = []
                while idx < len(blines):
                    cur_l = blines[idx]
                    if "{" in cur_l:
                        before, after = cur_l.split("{", 1)
                        sig_lines.append(before)
                        break
                    else:
                        sig_lines.append(cur_l)
                        idx += 1
                sig_text = " ".join(s.strip() for s in sig_lines)
                kind, ret_type, sel, params = parse_method_sig(sig_text)

                # Collect method body until matching '}'
                body_lines = [after]
                depth = 1
                clean_after = re.sub(r"//.*", "", re.sub(r'"([^"\\]|\\.)*"', '""', after))
                depth += clean_after.count("{") - clean_after.count("}")
                idx += 1
                while idx < len(blines) and depth > 0:
                    cur_l = blines[idx]
                    clean = re.sub(r"//.*", "", re.sub(r'"([^"\\]|\\.)*"', '""', cur_l))
                    depth += clean.count("{") - clean.count("}")
                    if depth == 0:
                        body_lines.append(cur_l.rsplit("}", 1)[0])
                    else:
                        body_lines.append(cur_l)
                    idx += 1

                body = "\n".join(body_lines)
                mcount += 1
                safe_sel = sel.replace(":", "$")
                orig_var = f"_logos_orig_{cls_name}_{safe_sel}_{mcount}"
                fn_name = f"_logos_method_{cls_name}_{safe_sel}_{mcount}"
                self_type = "Class " if kind == "+" else f"{cls_name} *"
                fn_params = [f"{self_type}self", "SEL _cmd"] + [f"{pt} {pn}" for pt, pn in params]
                orig_ptypes = ["id", "SEL"] + [pt for pt, _ in params]

                body = replace_percent_c(body)
                super_var = f"_logos_cls_{super_name}" if is_sub else ""
                body = replace_orig(body, is_sub, super_var, orig_var, ret_type, sel, params, kind)

                if not is_sub and not pending_new:
                    out.append(f"static {ret_type} (*{orig_var})({', '.join(orig_ptypes)});")
                out.append(f"static {ret_type} {fn_name}({', '.join(fn_params)}) {{")
                out.append(body)
                out.append("}")
                out.append("")

                if is_sub or pending_new:
                    enc_parts = [objc_type_encoding_expr(ret_type), '"@"', '":"'] + [objc_type_encoding_expr(pt) for pt, _ in params]
                    enc_expr = f'[[NSString stringWithFormat:@"%s", ""] stringByAppendingString:@""]'  # unused
                    # Build std::string for type encoding
                    concat = " + ".join([f"std::string({e})" for e in enc_parts])
                    target_cls = f"_logos_cls_{cls_name}" if kind == "-" else f"object_getClass((id)_logos_cls_{cls_name})"
                    init_registrations.append(f'    {{ std::string enc = {concat}; class_addMethod({target_cls}, @selector({sel}), (IMP){fn_name}, enc.c_str()); }}')
                else:
                    target_cls = f"_logos_cls_{cls_name}" if kind == "-" else f"object_getClass((id)_logos_cls_{cls_name})"
                    init_registrations.append(
                        f'    _logos_register_hook({target_cls}, @selector({sel}), (IMP){fn_name}, (IMP *)&{orig_var});'
                    )
                pending_new = False
                continue

            idx += 1

        if is_sub:
            init_registrations.append(f"    objc_registerClassPair(_logos_cls_{cls_name});")

    # Emit #include <string> near top if needed
    out.insert(2, "#include <string>")

    # Process %ctor and %init(...)
    ctor_body = "\n".join(ctor_lines)
    # Parse %init(A = expr, B = expr)
    m_init = re.search(r"%init\s*\((.*?)\)\s*;", ctor_body, flags=re.S)
    overrides = {}
    if m_init:
        for pair in split_top_level_args(m_init.group(1)):
            if "=" in pair:
                k, v = pair.split("=", 1)
                overrides[k.strip()] = v.strip()
        init_code_lines = []
        for cls in sorted(all_classes):
            if cls in overrides:
                init_code_lines.append(f"    _logos_cls_{cls} = {overrides[cls]};")
            else:
                # subclasses are allocated in init_registrations
                if not any(is_sub and c == cls for is_sub, c, _, _ in blocks):
                    init_code_lines.append(f'    _logos_cls_{cls} = objc_getClass("{cls}");')
        init_code_lines.extend(init_registrations)
        ctor_body = ctor_body[: m_init.start()] + "\n".join(init_code_lines) + ctor_body[m_init.end() :]

    ctor_body = replace_percent_c(ctor_body)
    out.append("__attribute__((constructor))")
    out.append("static void _logos_ctor(void) {")
    out.append(ctor_body)
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <input.xm> <output.mm>")
    src = Path(sys.argv[1]).read_text(encoding="utf-8")
    Path(sys.argv[2]).write_text(translate(src), encoding="utf-8")


if __name__ == "__main__":
    main()
