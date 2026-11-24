"""扫描 Dart 源码里的中文字符串字面量。

为什么不用正则：`'${DateFormat('HH:mm').format(t)} 结束'` 这种嵌套引号会把
正则切碎，产生一堆假条目。这里按字符扫，遇到 `${...}` 递归跳过内部代码。

输出：
  literal  纯文本字面量（原样，含 \\n 转义）
  template 含插值的字面量，表达式按顺序替换成 {}，并给出参数个数
"""
import os
import re
import sys
import json
import collections

CN = re.compile(r'[\u4e00-\u9fa5]')


def skip_string(s, i):
    """s[i] 是引号起始（可能带 r 前缀）。返回 (content, exprs, end_index)。

    exprs 是每个 ${...} 的内部代码原文（不含 ${ }）。
    """
    raw = False
    if s[i] == 'r' and i + 1 < len(s) and s[i + 1] in '\'"':
        raw = True
        i += 1
    quote = s[i]
    triple = s[i:i + 3] == quote * 3
    if triple:
        i += 3
        closer = quote * 3
    else:
        i += 1
        closer = quote

    buf = []
    exprs = []
    while i < len(s):
        if s.startswith(closer, i):
            return ''.join(buf), exprs, i + len(closer)
        ch = s[i]
        if not raw and ch == '\\':
            buf.append(s[i:i + 2])
            i += 2
            continue
        if not raw and s.startswith('${', i):
            i += 2
            depth = 1
            start = i
            while i < len(s) and depth > 0:
                c = s[i]
                if c in '\'"':
                    _, _, end = skip_string(s, i)
                    i = end
                    continue
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            exprs.append(s[start:i])
            buf.append('{}')
            i += 1
            continue
        if not raw and ch == '$':
            m = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*)', s[i:])
            if m:
                exprs.append(m.group(1))
                buf.append('{}')
                i += m.end()
                continue
        buf.append(ch)
        i += 1
    return ''.join(buf), exprs, i


def scan(path):
    s = open(path, encoding='utf-8').read()
    out = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == '/' and i + 1 < n and s[i + 1] == '/':
            j = s.find('\n', i)
            i = n if j < 0 else j
            continue
        if ch == '/' and i + 1 < n and s[i + 1] == '*':
            j = s.find('*/', i)
            i = n if j < 0 else j + 2
            continue
        if ch in '\'"' or (ch == 'r' and i + 1 < n and s[i + 1] in '\'"'):
            start = i
            # 三引号字符串里可能有换行，行号按开始位置算
            content, exprs, end = skip_string(s, i)
            if CN.search(content):
                line = s.count('\n', 0, start) + 1
                out.append({
                    'file': path,
                    'line': line,
                    'start': start,
                    'end': end,
                    'text': content,
                    'exprs': exprs,
                })
            i = end
            continue
        i += 1
    return out


def main():
    files = []
    for root, _, names in os.walk('lib'):
        for f in names:
            if f.endswith('.dart') and not f.endswith('.g.dart'):
                files.append(os.path.join(root, f))
    files.sort()
    hits = []
    for p in files:
        hits.extend(scan(p))

    literal = collections.Counter()
    template = collections.Counter()
    for h in hits:
        if h['exprs']:
            template[h['text']] += 1
        else:
            literal[h['text']] += 1

    with open('../tmp2_hits.json', 'w', encoding='utf-8') as f:
        json.dump(hits, f, ensure_ascii=False)
    with open('../tmp2_plain.txt', 'w', encoding='utf-8') as f:
        for k in sorted(literal):
            f.write(k + '\n')
    with open('../tmp2_tpl.txt', 'w', encoding='utf-8') as f:
        for k in sorted(template):
            f.write(k + '\n')
    print('hits', len(hits), 'literal', len(literal), 'template', len(template))


if __name__ == '__main__':
    sys.exit(main())
