#!/usr/bin/env python3
"""Generate ca65 source for HOPPER from the original tape image.

Usage:  python3 tools/gen_source.py original/HOPPER.TAP src/hopper.s

How it works
  1. Extract the single machine-code block from the TAP file.
  2. Trace code by recursive descent from the entry points in annotations.py
     (following branches, JSR and JMP abs). Everything not reached is data.
  3. Emit one instruction per line with labels for every in-program target,
     and data as .byte / .res lines split at every referenced address.

The output must assemble back to a byte-identical TAP (run `make verify`).
Names and comments come from tools/annotations.py, so improving that file
and regenerating is the easiest way to document the game further.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from m6502 import OPS, SIZES  # noqa: E402
import annotations as A  # noqa: E402


def read_tap(path):
    raw = open(path, "rb").read()
    i = 0
    while raw[i] == 0x16:
        i += 1
    assert raw[i] == 0x24, "no TAP sync marker"
    h = raw[i + 1:i + 10]
    end = h[4] << 8 | h[5]
    start = h[6] << 8 | h[7]
    j = i + 10
    while raw[j]:
        j += 1
    j += 1
    data = raw[j:j + end - start + 1]
    assert len(data) == end - start + 1
    return start, data, h


def main(tap, out):
    base, data, hdr = read_tap(tap)
    END = base + len(data)

    def byte(a):
        return data[a - base]

    def word(a):
        return byte(a) | byte(a + 1) << 8

    # ---------- 1. trace -------------------------------------------------
    ins = {}                     # addr -> (mn, mode, operand, size)
    jsr_targets, jump_targets, data_refs, ext_refs = set(), set(), set(), {}
    illegal = set()
    todo = list(A.ENTRIES) + [a for a, _ in A.DEAD_CODE]
    while todo:
        pc = todo.pop()
        while base <= pc < END and pc not in ins:
            op = byte(pc)
            if op not in OPS:
                illegal.add(pc)
                break
            mn, mode = OPS[op]
            n = SIZES[mode]
            if pc + n >= END:
                break
            opd = byte(pc + 1) if n == 1 else (word(pc + 1) if n == 2 else None)
            nxt = pc + 1 + n
            if mode == "rel":
                opd = (nxt + (opd - 256 if opd > 127 else opd)) & 0xFFFF
                jump_targets.add(opd)
                todo.append(opd)
            ins[pc] = (mn, mode, opd, n + 1)
            if mn in ("jsr", "jmp") and mode == "abs":
                if base <= opd < END:
                    (jsr_targets if mn == "jsr" else jump_targets).add(opd)
                    todo.append(opd)
            elif mode in ("abs", "abx", "aby", "ind"):
                if base <= opd < END:
                    data_refs.add(opd)
            if mn in ("rts", "rti", "brk", "jmp"):
                break
            pc = nxt

    # Resolve overlapping decodings: keep instructions greedily by address.
    code_owner = {}              # byte addr -> instruction start
    kept = []
    for a in sorted(ins):
        if a in code_owner:
            continue             # starts inside an earlier instruction
        size = ins[a][3]
        if any(x in code_owner for x in range(a, a + size)):
            continue
        kept.append(a)
        for x in range(a, a + size):
            code_owner[x] = a
    kept_set = set(kept)

    # ---------- 2. labels --------------------------------------------------
    targets = jsr_targets | jump_targets | data_refs | set(A.LABELS) \
        | set(A.ENTRIES) | {a for a, _ in A.DEAD_CODE} | set(A.DATA_SPLITS) | set(A.BLOCKS)
    targets = {t for t in targets if base <= t < END}

    # Data blocks: references inside a block become name+offset.
    block_of = {}
    for bs, (bname, bsize, _fmt, _c) in A.BLOCKS.items():
        for x in range(bs, bs + bsize):
            assert x not in code_owner, f"block {bname} overlaps code at ${x:04X}"
            block_of[x] = bs
    targets = {t for t in targets if t not in block_of or t in A.BLOCKS}
    names = {}
    for t in targets:
        if t in A.BLOCKS:
            names[t] = A.BLOCKS[t][0]
        elif t in A.LABELS:
            names[t] = A.LABELS[t]
        elif t in jsr_targets:
            names[t] = f"sub_{t:04X}"
        elif t in code_owner:
            names[t] = f"L{t:04X}"
        else:
            names[t] = f"D{t:04X}"
    mid_labels = {t for t in targets if t in code_owner and code_owner[t] != t}

    def ext_name(a, zp):
        if a in A.SYMBOLS:
            return A.SYMBOLS[a]
        if 0xBB80 <= a < 0xBFE0:            # text screen: show row/column
            r, c = divmod(a - 0xBB80, 40)
            return f"SCREEN+{r}*40+{c}"
        if 0xB400 <= a < 0xB800:            # standard character set
            ch, o = divmod(a - 0xB400, 8)
            return f"CHARSET+${ch:02X}*8" + (f"+{o}" if o else "")
        if 0xB800 <= a < 0xBB80:            # alternate character set
            return f"ALTCHARS+${a - 0xB800:03X}"
        ext_refs[a] = True
        return f"${a:02X}" if zp else f"${a:04X}"

    def fmt_operand(mn, mode, v):
        if mode in ("imp",):
            return ""
        if mode == "acc":
            return "a"
        if mode == "imm":
            return f"#${v:02X}"
        if mode in ("zp", "zpx", "zpy", "izx", "izy"):
            s = ext_name(v, True)
            return {"zp": s, "zpx": f"{s},x", "zpy": f"{s},y",
                    "izx": f"({s},x)", "izy": f"({s}),y"}[mode]
        # absolute / relative
        if v in A.EXPR:
            s = A.EXPR[v]
        elif v in block_of and v not in A.BLOCKS:
            bs = block_of[v]
            s = f"{A.BLOCKS[bs][0]}+{v - bs}"
        elif base <= v < END:
            s = names[v]
        else:
            s = ext_name(v, False)
        if v < 0x100 and mode != "rel":
            s = "a:" + s         # original used absolute mode; keep it (ca65 would pick zp)
        return {"rel": s, "abs": s, "abx": f"{s},x", "aby": f"{s},y",
                "ind": f"({s})"}[mode]

    # ---------- 3. emit ----------------------------------------------------
    L = []
    w = L.append
    for line in A.FILE_HEADER.strip("\n").splitlines():
        w(line)
    w("")
    w('        .include "oric.inc"')
    w('        .include "vars.inc"')
    w("")
    w(";------------------------------------------------------------------------------")
    w("; Oric tape header (see README). End address is inclusive.")
    w(";------------------------------------------------------------------------------")
    w('        .segment "TAPEHDR"')
    w("        .byte   $16,$16,$16,$24     ; sync bytes + start marker")
    w(f"        .byte   ${hdr[0]:02X},${hdr[1]:02X}             ; unused")
    w(f"        .byte   ${hdr[2]:02X}                 ; file type: $80 = machine code")
    w(f"        .byte   ${hdr[3]:02X}                 ; autorun: $C7 = run after load")
    w("        .dbyt   PROG_END-1          ; end address (big-endian)")
    w("        .dbyt   PROG_START          ; start address (big-endian)")
    w(f"        .byte   ${hdr[8]:02X}                 ; unused")
    w("        .byte   $00                 ; filename (empty) terminator")
    w("")
    w('        .segment "CODE"')
    w("PROG_START:")

    COL_OP, COL_CMT = 8, 40

    def pad(s, n):
        return s + " " * max(1, n - len(s))

    def emit_label(a):
        hdr = A.BLOCK_COMMENTS.get(a) or (A.BLOCKS[a][3] if a in A.BLOCKS else None)
        if hdr:
            w("")
            w(";" + "-" * 78)
            for c in hdr.strip("\n").splitlines():
                w(("; " + c).rstrip())
            w(";" + "-" * 78)
        elif a in jsr_targets or a in A.ENTRIES:
            w("")
        if a in names and a not in mid_labels:
            w(names[a] + ":")

    dead_starts = dict(A.DEAD_CODE)
    a = base
    while a < END:
        if a in dead_starts:
            w("")
            w(f"; ---- unreferenced code: {dead_starts[a]}")
        if a in kept_set:
            emit_label(a)
            mn, mode, v, size = ins[a]
            op = fmt_operand(mn, mode, v)
            text = " " * COL_OP + pad(mn, 8) + op
            cmt = A.COMMENTS.get(a, "")
            w(pad(text, COL_CMT) + f"; {a:04X}" + (f"  {cmt}" if cmt else ""))
            for t in sorted(mid_labels):
                if a < t < a + size:
                    w(f"{names[t]} := * - {a + size - t}"
                      f"          ; {t:04X}: target inside instruction above")
            a += size
            continue
        if a in A.BLOCKS:
            emit_label(a)
            bname, bsize, fmt, bcmt = A.BLOCKS[a]
            if bcmt and a not in A.BLOCK_COMMENTS:
                pass
            emit_block(w, data, base, a, bsize, fmt)
            a += bsize
            continue
        # data run: up to next label / code / split / block
        emit_label(a)
        s = a
        a += 1
        while a < END and a not in kept_set and a not in targets and a not in dead_starts \
                and a not in A.BLOCKS:
            a += 1
        emit_data(w, data, base, s, a, A)

    w("")
    w("PROG_END:")
    open(out, "w").write("\n".join(L) + "\n")

    # report
    print(f"code bytes: {len(code_owner)} / {len(data)}")
    print(f"instructions: {len(kept)}  labels: {len(names)}")
    if illegal:
        print("illegal opcodes reached at:", " ".join(f"${x:04X}" for x in sorted(illegal)))
    if mid_labels:
        print("targets inside instructions:", " ".join(f"${x:04X}" for x in sorted(mid_labels)))
    smc = sorted({a for a in kept if ins[a][0] in ("sta", "stx", "sty", "inc", "dec")
                  and ins[a][1] in ("abs", "abx", "aby") and ins[a][2] in code_owner})
    if smc:
        print("self-modifying stores at:", " ".join(f"${x:04X}" for x in smc))
    unnamed = sorted(x for x in ext_refs if x not in A.SYMBOLS)
    if unnamed:
        print("unnamed external addresses:", " ".join(f"${x:04X}" for x in unnamed))


def emit_block(w, data, base, s, size, fmt):
    """Emit a named data block in a given format."""
    def pad(t, n):
        return t + " " * max(1, n - len(t))
    blk = data[s - base:s - base + size]
    kind, _, arg = fmt.partition(":")
    if kind == "glyph":                       # character graphics, 8 bytes/char
        ch = int(arg, 16) if arg else None
        for i, b in enumerate(blk):
            pic = "".join("#" if b & (1 << k) else "." for k in range(5, -1, -1))
            note = ""
            if i % 8 == 0:
                note = f"  char ${ch + i // 8:02X}" if ch is not None else f"  +{i}"
            w(pad(f"        .byte   %{b:08b}", 40) + f"; {s + i:04X} {pic}{note}")
    elif kind == "word":
        for i in range(0, size, 2):
            v = blk[i] | blk[i + 1] << 8
            w(pad(f"        .word   ${v:04X}", 40) + f"; {s + i:04X}")
    elif kind == "bytes":
        n = int(arg) if arg else 8
        for i in range(0, size, n):
            row = blk[i:i + n]
            w(pad("        .byte   " + ",".join(f"${x:02X}" for x in row), 58) + f"; {s + i:04X}")
    elif kind == "text":                      # strings with control codes, split at CR
        line, start = [], s
        i = 0
        def flush():
            if line:
                w(pad("        .byte   " + ",".join(line), 58) + f"; {start:04X}")
        while i < size:
            b = blk[i]
            if 0x20 <= b < 0x7F and b != 0x22:
                j = i
                while j < size and 0x20 <= blk[j] < 0x7F and blk[j] != 0x22 and j - i < 36:
                    j += 1
                line.append('"' + blk[i:j].decode() + '"')
                i = j
            else:
                line.append(f"${b:02X}")
                i += 1
            if b == 0x0D or len(line) >= 6 or i >= size:
                flush()
                line, start = [], s + i
        flush()
    else:
        emit_data(w, data, base, s, s + size, None)


def emit_data(w, data, base, s, e, A):
    """Emit bytes s..e-1 as .res fills, strings and .byte rows."""
    def pad(t, n):
        return t + " " * max(1, n - len(t))
    a = s
    while a < e:
        b = data[a - base]
        run = a
        while run < e and data[run - base] == b:
            run += 1
        if run - a >= 4:
            w(pad(f"        .res    {run - a}, ${b:02X}", 40) + f"; {a:04X}")
            a = run
            continue
        t = a
        while t < e and 0x20 <= data[t - base] < 0x7F and data[t - base] != 0x22:
            t += 1
        if t - a >= 5:
            chunk = data[a - base:t - base]
            while chunk:
                part, chunk = chunk[:40], chunk[40:]
                w(pad(f'        .byte   "{part.decode()}"', 58) + f"; {a:04X}")
                a += len(part)
            continue
        row = []
        st = a
        while a < e and len(row) < 8:
            row.append(data[a - base])
            a += 1
            if a < e and data[a - base] == data[a - 1 - base] and \
                    a + 3 <= e and len(set(data[a - base:a - base + 4])) == 1:
                break
        w(pad("        .byte   " + ",".join(f"${x:02X}" for x in row), 58) + f"; {st:04X}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
