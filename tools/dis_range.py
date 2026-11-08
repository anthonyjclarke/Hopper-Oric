"""Quick linear disassembly of a range of the extracted binary: dis_range.py START END"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from m6502 import OPS, SIZES
from gen_source import read_tap
BASE, d, _ = read_tap(os.path.join(os.path.dirname(__file__), '..', 'original', 'HOPPER.TAP'))
pc, end = int(sys.argv[1], 16), int(sys.argv[2], 16)
while pc < end:
    op = d[pc-BASE]
    if op not in OPS:
        print(f'{pc:04X}  {op:02X}        .byte ${op:02X}'); pc += 1; continue
    mn, mode = OPS[op]; n = SIZES[mode]
    raw = d[pc-BASE:pc-BASE+1+n]
    v = raw[1] if n == 1 else (raw[1] | raw[2] << 8 if n == 2 else 0)
    f = {'imp':'','acc':'a','imm':f'#${v:02X}','zp':f'${v:02X}','zpx':f'${v:02X},x','zpy':f'${v:02X},y',
         'izx':f'(${v:02X},x)','izy':f'(${v:02X}),y','abs':f'${v:04X}','abx':f'${v:04X},x','aby':f'${v:04X},y',
         'ind':f'(${v:04X})','rel':f'${(pc+2+(v-256 if v>127 else v))&0xffff:04X}'}[mode]
    print(f'{pc:04X}  {raw.hex(" "):9} {mn} {f}')
    pc += 1 + n
