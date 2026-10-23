"""Run isolated XSim tests; no original project is opened or changed.

If the bundled GCC cannot start in the managed environment, compile XSim's
generated C driver with the installed Vivado LLVM and build local import libs.
HDL elaboration and simulation remain XSim, not an emulated CPU implementation.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import shutil

ROOT = Path(__file__).resolve().parents[1]

def command(args, cwd, logfile, env=None, timeout=180):
    args = list(map(str, args))
    if args[0].lower().endswith('.bat'):
        args = [os.environ.get('COMSPEC', 'cmd.exe'), '/d', '/c', *args]
    try:
        result = subprocess.run(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        partial=(exc.stdout or b'').decode('utf-8',errors='replace')
        Path(logfile).write_text(partial+'\nTIMEOUT: process did not finish.\n',encoding='utf-8')
        raise
    output = result.stdout.decode('utf-8', errors='replace')
    Path(logfile).write_text(output, encoding='utf-8')
    return result.returncode, output

def llvm_link(vivado, build, snapshot):
    llvm = vivado / 'tps/llvm/7.0/win64/bin'
    mingw = vivado / 'tps/mingw/9.3.0/win64.o/nt'
    obj = build / 'xsim.dir' / snapshot / 'obj'
    common = [llvm/'clang.exe', '--target=x86_64-w64-windows-gnu',
              '--sysroot='+str(mingw/'x86_64-w64-mingw32')]
    for source in obj.glob('*.c'):
        rc, out = command([*common, '-I', vivado/'data/xsim/include', '-c', source,
                           '-o', source.with_suffix('.win64.obj')], build,
                          build/(source.stem+'_clang.log'))
        if rc:
            raise RuntimeError(out)
    libs = []
    for name in ('librdi_simulator_kernel', 'librdi_simbridge_kernel'):
        dll = vivado/'lib/win64.o'/(name+'.dll')
        rc, out = command([llvm/'llvm-readobj.exe', '--coff-exports', dll], build,
                          build/(name+'_exports.log'))
        if rc:
            raise RuntimeError(out)
        names = re.findall(r'^\s+Name: ([A-Za-z_][A-Za-z_0-9]*)\s*$', out, re.M)
        definition = build/(name+'.def')
        definition.write_text('LIBRARY '+name+'.dll\nEXPORTS\n'+'\n'.join(names)+'\n')
        lib = build/(name+'.a')
        rc, out = command([llvm/'llvm-dlltool.exe', '-m', 'i386:x86-64',
                           '-d', definition, '-l', lib], build, build/(name+'_import.log'))
        if rc:
            raise RuntimeError(out)
        libs.append(lib)
    rc, out = command([*common, '-fuse-ld=lld', '-L',
                       mingw/'lib/gcc/x86_64-w64-mingw32/9.3.0',
                       *sorted(obj.glob('*.obj')), *libs,
                       '-Wl,--stack,104857600', '-Wl,--image-base,0x400000', '-o',
                       build/'xsim.dir'/snapshot/'xsimk.exe'],
                      build, build/'llvm_link.log')
    if rc:
        raise RuntimeError(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('test', choices=['predictor','uart','cpu_branch','soc_uart','ex8','ex9'])
    ap.add_argument('--vivado', default='D:/Vivado/Vivado/2023.2')
    ap.add_argument('--llvm-fallback',action='store_true',
                    help='Experimental local diagnostic; not required in a working Vivado installation')
    ns=ap.parse_args()
    vivado=Path(ns.vivado)
    build=ROOT/'build'/ns.test
    build.mkdir(parents=True,exist_ok=True)
    cpu_dir=ROOT/'mycpu_env/myCPU'
    rtl_dir=ROOT/'mycpu_env/soc_verify/soc_bram/rtl'
    if ns.test=='predictor': files=[cpu_dir/'branch_predictor.v']
    elif ns.test=='uart': files=[rtl_dir/'uart_mmio.v']
    else:
        files=sorted(cpu_dir.glob('*.v'))+[ROOT/'tests/sim_models.sv']
        if ns.test!='cpu_branch':
            files += [rtl_dir/'uart_mmio.v',rtl_dir/'soc_lite_top.v',
                      rtl_dir/'BRIDGE/bridge_1x2.v',rtl_dir/'CONFREG/confreg.v']
        image={'cpu_branch':'branch_bench','soc_uart':'uart_irq_echo'}.get(ns.test,ns.test)
        image_dir=(ROOT/'for_test_obj'/(image+'_obj') if ns.test in ('ex8','ex9')
                   else ROOT/'software'/image)
        for name in ('inst_ram.mif','data_ram.mif'):
            shutil.copy2(image_dir/name,build/name)
    top='tb_'+ns.test
    if ns.test in ('ex8','ex9'):
        files.append(ROOT/'mycpu_env/soc_verify/soc_bram/testbench/mycpu_tb.v')
        top='tb_top'
        if ns.test=='ex9': shutil.copy2(ROOT/'baseline/ex9_golden_trace.txt',build/'golden_trace.txt')
    else: files.append(ROOT/'tests'/('tb_'+ns.test+'.sv'))
    rc,out=command([vivado/'bin/xvlog.bat','-sv','-i',cpu_dir,*files],build,build/'compile.log')
    if rc: raise RuntimeError(out)
    snapshot=ns.test+'_standalone'
    generics=['--generic_top','TRACE_ENABLE=0'] if ns.test=='ex8' else []
    rc,out=command([vivado/'bin/xelab.bat','work.'+top,'-s',snapshot,*generics,
                    '--standalone','--mt','off','--timescale','1ns/1ps'],
                   build,build/'elaborate.log')
    if rc:
        if not ns.llvm_fallback or 'Failed to compile generated C file' not in out:
            raise RuntimeError(out+'\nSimulation did not run. No PASS is claimed.')
        print('Using installed LLVM for generated XSim C driver (GCC unavailable).')
        llvm_link(vivado,build,snapshot)
    task_env=dict(os.environ)
    task_env['PATH']=str(vivado/'lib/win64.o')+';'+str(vivado/'tps/mingw/9.3.0/win64.o/nt/bin')+';'+task_env.get('PATH','')
    task_env['XILINX_VIVADO']=str(vivado)
    rc,out=command([build/'xsim.dir'/snapshot/'xsimk.exe'],build,build/'simulate.log',env=task_env,
                    timeout=600 if ns.test in ('ex8','ex9') else 45)
    print(out)
    passed=('----PASS!!!' in out if ns.test in ('ex8','ex9') else 'PASS ' in out)
    if rc or not passed or 'Fatal:' in out or 'Error!!!' in out:
        raise RuntimeError('Test did not report PASS; see '+str(build/'simulate.log'))

if __name__=='__main__':
    try: main()
    except Exception as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(1)
