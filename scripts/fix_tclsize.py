#!/usr/bin/env python3
"""Fix Tcl 9 int*/Tcl_Size* out-parameter bugs from clang's warnings.

Input: lines "file:line:col" where clang reported
  incompatible pointer types passing 'int *' to parameter of type 'Tcl_Size *'
For each one whose argument is "&name" with a local variable, the variable's
declaration in the enclosing function becomes Tcl_Size (split out of a
multi-variable "int a, name, b;" if needed). Anything else is printed for
hand fixing. Line endings are preserved."""
import re, sys, collections

def split_top(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '([{': depth += 1
        if ch in ')]}': depth -= 1
        if ch == ',' and depth == 0: out.append(cur); cur = ''
        else: cur += ch
    out.append(cur); return out

todo = collections.defaultdict(list); manual = []
for l in open(sys.argv[1]):
    f, ln, col = l.strip().rsplit(':', 2)
    todo[f].append((int(ln), int(col)))
fixed = 0
for f, sites in todo.items():
    raw = open(f, 'rb').read().decode('latin-1')
    nl = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(nl)
    for ln, col in sorted(sites, reverse=True):
        src = lines[ln - 1]
        m = re.match(r'&\s*([A-Za-z_]\w*)\b(?!\s*(?:->|\.|\[))', src[col - 1:])
        if not m: manual.append((f, ln, src.strip())); continue
        name = m.group(1)
        # enclosing function: back to the last line that is exactly "{" or a "^\w...(" signature
        start = ln - 1
        while start > 0 and lines[start] != '{' and not re.match(r'^\{', lines[start]): start -= 1
        done = False
        for i in range(ln - 1, start - 1, -1):
            d = re.match(r'^(\s*)((?:static\s+|register\s+|unsigned\s+)*)int\s+(.*?);(.*)$', lines[i])
            if not d: continue
            decls = split_top(d.group(3))
            names = [re.match(r'\s*\**\s*([A-Za-z_]\w*)', x).group(1) if re.match(r'\s*\**\s*([A-Za-z_]\w*)', x) else None for x in decls]
            if name not in names: continue
            k = names.index(name); this = decls[k].strip()
            if this.startswith('*') or 'unsigned' in d.group(2):
                manual.append((f, ln, src.strip())); done = True; break
            rest = [x.strip() for j, x in enumerate(decls) if j != k]
            new = d.group(1) + 'Tcl_Size ' + this + ';'
            if rest:
                lines[i] = d.group(1) + d.group(2) + 'int ' + ', '.join(rest) + ';' + d.group(4)
                lines.insert(i + 1, new)
            else:
                lines[i] = new + d.group(4)
            fixed += 1; done = True; break
        if not done:
            # a parameter of the enclosing function ("int objc" in an ObjCmd/coord proc): keep the
            # signature, rename the parameter and shadow it with a Tcl_Size copy under the old name
            sig = start - 1
            while sig > 0 and not re.match(r'^[A-Za-z_]', lines[sig]): sig -= 1
            for i in range(sig, start):
                if re.search(r'\bint\s+' + name + r'\b(?!\s*\[)', lines[i]) and 'Tcl_Size ' + name + ' = ' + name + '_in' not in lines[start + 1]:
                    lines[i] = re.sub(r'\bint(\s+)' + name + r'\b', r'int\1' + name + '_in', lines[i], count=1)
                    lines.insert(start + 1, '    Tcl_Size ' + name + ' = ' + name + '_in;')
                    fixed += 1; done = True; break
                if 'Tcl_Size ' + name + ' = ' + name + '_in' in lines[start + 1]: done = True; break
        if not done: manual.append((f, ln, src.strip()))
    open(f, 'wb').write(nl.join(lines).encode('latin-1'))
print('fixed', fixed)
for m in manual: print('MANUAL', m[0].split('/jni/')[-1], m[1], m[2][:110])
