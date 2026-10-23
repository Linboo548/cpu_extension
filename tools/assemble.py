"""Small, checked LA32R demo assembler, not a replacement for the GNU toolchain.
Supported instructions are deliberately limited to those used by software/*.S.
Each `li`/`la` is always two instructions so both passes agree on label addresses.
Produces portable RAM initialization artifacts without installing a cross compiler.
"""
import argparse
import ast
from pathlib import Path
import re

BASE=0x1C000000

def expression(s,names):
    def visit(node):
        if isinstance(node,ast.Constant) and isinstance(node.value,int): return node.value
        if isinstance(node,ast.Name): return names[node.id]
        if isinstance(node,ast.UnaryOp) and isinstance(node.op,ast.USub): return -visit(node.operand)
        if isinstance(node,ast.BinOp):
            a,b=visit(node.left),visit(node.right)
            if isinstance(node.op,ast.Add): return a+b
            if isinstance(node.op,ast.Sub): return a-b
            if isinstance(node.op,ast.LShift): return a<<b
            if isinstance(node.op,ast.BitOr): return a|b
        raise ValueError('unsupported expression: '+s)
    return visit(ast.parse(s.strip(),mode='eval').body)

def reg(s):
    m=re.fullmatch(r'\$?r(\d+)',s.strip())
    if not m or not 0<=int(m[1])<32: raise ValueError('bad register '+s)
    return int(m[1])

def bounded(n,bits,signed=False):
    lo=-(1<<(bits-1)) if signed else 0
    hi=(1<<(bits-1))-1 if signed else (1<<bits)-1
    if not lo<=n<=hi: raise ValueError(f'{n} does not fit {bits} bits (signed={signed})')
    return n&((1<<bits)-1)

def assemble(source):
    names={}; entries=[]; pc=BASE
    for line_no,line in enumerate(source.splitlines(),1):
        line=line.split('#',1)[0].split('//',1)[0].strip()
        if not line: continue
        if ':' in line:
            label,line=line.split(':',1)
            if label.strip() in names: raise ValueError('duplicate label '+label)
            names[label.strip()]=pc
            line=line.strip()
            if not line: continue
        fields=line.split(None,1); op=fields[0].lower()
        args=[s.strip() for s in fields[1].split(',')] if len(fields)>1 else []
        if op=='.equ': names[args[0]]=expression(args[1],names); continue
        if op in ('.text','.global','.globl'): continue
        if op=='.org':
            newpc=expression(args[0],names)
            if newpc<pc or newpc<BASE or newpc%4: raise ValueError('invalid .org')
            pc=newpc;continue
        entries.append((pc,op,args,line_no))
        pc+=8 if op in ('li','la') else 4
    words={}
    for pc,op,a,line_no in entries:
        try:
            e=lambda s:expression(s,names)
            if op in ('li','la'):
                d=reg(a[0]);v=e(a[1])&0xffffffff
                codes=[0x14000000|((v>>12)<<5)|d,0x03800000|((v&4095)<<10)|(d<<5)|d]
            elif op=='.word': codes=[e(a[0])&0xffffffff]
            elif op=='nop': codes=[0x03400000]
            elif op=='ertn': codes=[0x06483800]
            elif op in ('syscall','break'):
                codes=[(0x002b0000 if op=='syscall' else 0x002a0000)|bounded(e(a[0]) if a else 0,15)]
            elif op in ('lu12i.w','pcaddu12i'):
                codes=[(0x14000000 if op=='lu12i.w' else 0x1c000000)|((e(a[1])&0xfffff)<<5)|reg(a[0])]
            elif op in ('csrrd','csrwr','csrxchg'):
                j=0 if op=='csrrd' else 1 if op=='csrwr' else reg(a[1])
                if op=='csrxchg' and j<2: raise ValueError('csrxchg mask register must not be r0/r1')
                codes=[0x04000000|(bounded(e(a[-1]),14)<<10)|(j<<5)|reg(a[0])]
            elif op in ('b','bl'):
                delta=e(a[0])-pc
                if delta%4: raise ValueError('unaligned branch')
                v=bounded(delta//4,26,True)
                codes=[(0x50000000 if op=='b' else 0x54000000)|((v&0xffff)<<10)|(v>>16)]
            elif op in ('beq','bne','blt','bge','bltu','bgeu'):
                delta=e(a[2])-pc
                if delta%4: raise ValueError('unaligned branch')
                opcode={'beq':0x58,'bne':0x5c,'blt':0x60,'bge':0x64,'bltu':0x68,'bgeu':0x6c}[op]<<24
                codes=[opcode|(bounded(delta//4,16,True)<<10)|(reg(a[0])<<5)|reg(a[1])]
            elif op=='jirl':
                v=e(a[2])
                if v%4: raise ValueError('unaligned jirl offset')
                codes=[0x4c000000|(bounded(v//4,16,True)<<10)|(reg(a[1])<<5)|reg(a[0])]
            elif op in ('add.w','sub.w','and','or','xor','div.w'):
                opcode={'add.w':0x00100000,'sub.w':0x00110000,'and':0x00148000,'or':0x00150000,'xor':0x00158000,'div.w':0x00200000}[op]
                codes=[opcode|(reg(a[2])<<10)|(reg(a[1])<<5)|reg(a[0])]
            elif op in ('addi.w','andi','ori','xori','ld.w','st.w','ld.bu','st.b','slli.w','srli.w'):
                opcode={'addi.w':0x02800000,'andi':0x03400000,'ori':0x03800000,'xori':0x03c00000,
                        'ld.w':0x28800000,'st.w':0x29800000,'ld.bu':0x2a000000,'st.b':0x29000000,
                        'slli.w':0x00408000,'srli.w':0x00448000}[op]
                shift=op in ('slli.w','srli.w')
                signed=op in ('addi.w','ld.w','st.w','ld.bu','st.b')
                codes=[opcode|(bounded(e(a[2]),5 if shift else 12,signed)<<10)|(reg(a[1])<<5)|reg(a[0])]
            else: raise ValueError('unsupported instruction '+op)
            for i,code in enumerate(codes): words[(pc-BASE)//4+i]=code
        except Exception as ex: raise ValueError(f'line {line_no}, {op}: {ex}') from ex
    return words,names

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path)
    p.add_argument('--out',type=Path,required=True);p.add_argument('--full',action='store_true')
    ns=p.parse_args();words,names=assemble(ns.source.read_text(encoding='utf-8'))
    if words and max(words)>=262144: raise ValueError('program exceeds instruction BRAM')
    ns.out.mkdir(parents=True,exist_ok=True)
    (ns.out/'program.hex').write_text(''.join(f'@{i:08x}\n{v:08x}\n' for i,v in sorted(words.items())))
    (ns.out/'symbols.txt').write_text(''.join(f'{k} = 0x{v:08x}\n' for k,v in names.items()))
    if ns.full:
        values=[words.get(i,0x03400000) for i in range(262144)]
        (ns.out/'inst_ram.mif').write_text(''.join(f'{v:032b}\n' for v in values))
        (ns.out/'inst_ram.coe').write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n'+',\n'.join(f'{v:08x}' for v in values)+';\n')
        (ns.out/'data_ram.mif').write_text(('0'*32+'\n')*65536)
        (ns.out/'data_ram.coe').write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n'+',\n'.join(['00000000']*65536)+';\n')
    print(f'Assembled {ns.source.name}: {len(words)} words -> {ns.out}')
if __name__=='__main__': main()
