# -*- coding: utf-8 -*-
"""把翻译表生成 Dart 文件，并校验覆盖度。"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tr_plain_1 import PLAIN_1
from tr_plain_2 import PLAIN_2
from tr_plain_3 import PLAIN_3, TPL_3
from tr_tpl import TPL

TPL.update(TPL_3)

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BASE)

def _norm(d):
    '''键里的真实换行统一成转义形式，避免同一个键出现两份。'''
    out = {}
    for k, v in d.items():
        out[k.replace('\n', '\\n')] = v
    return out


PLAIN = {}
PLAIN.update(_norm(PLAIN_1))
PLAIN.update(_norm(PLAIN_2))
PLAIN.update(_norm(PLAIN_3))

# 不翻译的：DateFormat 格式串、正则、语言自身的名字
IGNORE_LITERAL = {
    "M月d日",
    "M月d日 EEEE",
    "M月d日 HH:mm",
    "yyyy 年 M 月",
    "yyyy年M月d日",
    "yyyy年M月d日 EEEE",
    "yyyy年M月",
    "中文",
    "English",
}


def load(name):
    '''读取 scan_cn.py 导出的清单；没有清单时跳过覆盖度检查，直接生成。'''
    p = os.path.join(os.path.dirname(ROOT), name)
    if not os.path.exists(p):
        return []
    with open(p, encoding='utf-8') as f:
        return [line.rstrip('\n') for line in f if line.strip()]


def is_regex(s):
    return bool(re.search(r'\\d|\(\?|\\s', s))


def main():
    plain = [x for x in load('tmp2_plain.txt')
             if x not in IGNORE_LITERAL and not is_regex(x)]
    tpl = load('tmp2_tpl.txt')

    missing_plain = [x for x in plain if x not in PLAIN]
    extra_plain = [x for x in PLAIN if x not in plain and '{}' not in x]
    missing_tpl = [x for x in tpl if x not in TPL]
    extra_tpl = [x for x in TPL if x not in tpl]

    if plain:
        print('plain: %d / %d covered' % (len(plain) - len(missing_plain), len(plain)))
    if tpl:
        print('tpl:   %d / %d covered' % (len(tpl) - len(missing_tpl), len(tpl)))
    if missing_plain:
        print('\n--- 缺少（源码有、表里没有）---')
        for x in missing_plain:
            print(repr(x))
    if missing_tpl:
        print('\n--- 缺少模板 ---')
        for x in missing_tpl:
            print(repr(x))
    if extra_plain:
        print('\n--- 多余（表里有、源码没有，可删）---')
        for x in extra_plain:
            print(repr(x))
    if extra_tpl:
        print('\n--- 多余模板 ---')
        for x in extra_tpl:
            print(repr(x))

    if '--write' not in sys.argv:
        return 0

    def esc(s):
        # 真实换行写成源码里的 \n 转义；不转义反斜杠本身，
        # 因为翻译表里的 \n 就是 Dart 源码里那个两字符的转义序列。
        s = s.replace('\n', '\\n')
        return s.replace("'", "\\'").replace('$', '\\$')

    lines = [
        '// 由 tools/gen_en.py 生成，勿手改；改 tools/tr_*.py 后重新生成。',
        '',
        '/// 静态文案：key 是中文原文。',
        'const Map<String, String> en = {',
    ]
    for k in sorted(PLAIN):
        lines.append("  '%s': '%s'," % (esc(k), esc(PLAIN[k])))
    lines.append('};')
    lines.append('')
    lines.append('/// 带插值的模板：key 里用 {} 占位。')
    lines.append('const Map<String, String> enTemplates = {')
    for k in sorted(TPL):
        lines.append("  '%s': '%s'," % (esc(k), esc(TPL[k])))
    lines.append('};')
    lines.append('')

    out = os.path.join(ROOT, 'lib/core/i18n/en.dart')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    print('\nwritten', out, 'plain', len(PLAIN), 'tpl', len(TPL))
    return 0


if __name__ == '__main__':
    sys.exit(main())
