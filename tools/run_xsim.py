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
        # Vivado's batch loader uses SHIFT, which splits unquoted NAME=VALUE.
        # Keep every argument quoted through cmd.exe instead of letting
        # subprocess.list2cmdline omit quotes around generic assignments.
        if any(any(char in arg for char in ('"', '\r', '\n')) for arg in args):
            raise ValueError('Unsupported quote/newline in batch tool argument')
        command_line=' '.join('"'+arg+'"' for arg in args)
        args=(subprocess.list2cmdline([os.environ.get('COMSPEC', 'cmd.exe'),
                                      '/d', '/s', '/c'])+' "'+command_line+'"')
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
    ap.add_argument('test', choices=['predictor','uart','cache','if_cache','cache_cpu',
                                    'cpu_branch','soc_uart','ex8','ex9'])
    ap.add_argument('--vivado', default=os.environ.get('XILINX_VIVADO',
                                                      'D:/Software/Vivado/2023.2'))
    ap.add_argument('--predictor', type=int, choices=(0, 1), default=1,
                    help='Prediction switch for SoC/ex8/ex9 regression (default: 1)')
    ap.add_argument('--cache', type=int, choices=(0, 1), default=1,
                    help='Enable both I/D caches for CPU/SoC regression (default: 1)')
    ap.add_argument('--build-root', type=Path, default=ROOT/'build'/'xsim',
                    help='Parent of isolated per-configuration result directories')
    ap.add_argument('--llvm-fallback',action='store_true',
                    help='Experimental local diagnostic; not required in a working Vivado installation')
    ns=ap.parse_args()
    vivado=Path(ns.vivado)
    cpu_tests = ('cpu_branch', 'soc_uart', 'ex8', 'ex9')
    if ns.test not in ('soc_uart', 'ex8', 'ex9') and not ns.predictor:
        ap.error('--predictor 0 is only supported for soc_uart/ex8/ex9')
    if ns.test not in cpu_tests and not ns.cache:
        ap.error('--cache 0 is only supported for cpu_branch/soc_uart/ex8/ex9')
    tag = ns.test
    if ns.test in ('soc_uart', 'ex8', 'ex9'):
        tag += '_bp'+str(ns.predictor)
    if ns.test in cpu_tests:
        tag += '_cache'+str(ns.cache)
    build=ns.build_root.resolve()/tag
    build.mkdir(parents=True,exist_ok=True)
    cpu_dir=ROOT/'mycpu_env/myCPU'
    rtl_dir=ROOT/'mycpu_env/soc_verify/soc_bram/rtl'
    if ns.test=='predictor': files=[cpu_dir/'branch_predictor.v']
    elif ns.test=='uart': files=[rtl_dir/'uart_mmio.v']
    elif ns.test=='cache': files=[cpu_dir/'cpu_sram_cache.v']
    elif ns.test=='if_cache': files=[cpu_dir/'branch_predictor.v', cpu_dir/'IF_stage.v']
    else:
        files=sorted(cpu_dir.glob('*.v'))+[ROOT/'tests/sim_models.sv']
        if ns.test not in ('cpu_branch', 'cache_cpu'):
            files += [rtl_dir/'uart_mmio.v',rtl_dir/'soc_lite_top.v',
                      rtl_dir/'BRIDGE/bridge_1x2.v',rtl_dir/'CONFREG/confreg.v']
        image={'cpu_branch':'branch_bench', 'cache_cpu':'cache_bench',
               'soc_uart':'uart_irq_echo'}.get(ns.test,ns.test)
        image_dir=(ROOT/'for_test_obj'/(image+'_obj') if ns.test in ('ex8','ex9')
                   else ROOT/'software'/image)
        if ns.test=='cache_cpu':
            image_dir=build/'image'
            rc,out=command([sys.executable, ROOT/'tools/assemble.py',
                            ROOT/'software/cache_bench.S', '--out', image_dir, '--full'],
                           build, build/'assemble.log')
            if rc: raise RuntimeError(out)
        for name in ('inst_ram.mif','data_ram.mif'):
            shutil.copy2(image_dir/name,build/name)
    top='tb_'+ns.test
    if ns.test in ('ex8','ex9'):
        files.append(ROOT/'mycpu_env/soc_verify/soc_bram/testbench/mycpu_tb.v')
        top='tb_top'
        if ns.test=='ex9' and not ns.predictor:
            files.append(ROOT/'tests/tb_ex9_bp0.sv')
            top='tb_ex9_bp0'
        if ns.test=='ex9': shutil.copy2(ROOT/'baseline/ex9_golden_trace.txt',build/'golden_trace.txt')
    else: files.append(ROOT/'tests'/('tb_'+ns.test+'.sv'))
    rc,out=command([vivado/'bin/xvlog.bat','-sv','-i',cpu_dir,*files],build,build/'compile.log')
    if rc: raise RuntimeError(out)
    snapshot=ns.test+'_standalone'
    generics=['--generic_top','TRACE_ENABLE=0'] if ns.test=='ex8' else []
    if ns.test in cpu_tests:
        generics += ['--generic_top', 'ICACHE_ENABLE='+str(ns.cache),
                     '--generic_top', 'DCACHE_ENABLE='+str(ns.cache)]
    if ns.test in ('soc_uart', 'ex8', 'ex9') and not (ns.test=='ex9' and not ns.predictor):
        generics += ['--generic_top', 'BR_PREDICT_ENABLE='+str(ns.predictor)]
    rc,out=command([vivado/'bin/xelab.bat','work.'+top,'-s',snapshot,*generics,
                    '--standalone','--mt','off','--timescale','1ns/1ps'],
                   build,build/'elaborate.log')
    used_llvm = False
    if rc:
        if not ns.llvm_fallback or 'Failed to compile generated C file' not in out:
            raise RuntimeError(out+'\nSimulation did not run. No PASS is claimed.')
        print('Using installed LLVM for generated XSim C driver (GCC unavailable).')
        llvm_link(vivado,build,snapshot)
        used_llvm = True
    task_env=dict(os.environ)
    task_env['PATH']=str(vivado/'lib/win64.o')+';'+str(vivado/'tps/mingw/9.3.0/win64.o/nt/bin')+';'+task_env.get('PATH','')
    task_env['XILINX_VIVADO']=str(vivado)
    snapshot_dir=build/'xsim.dir'/snapshot
    if used_llvm:
        # The fallback links xsimk.exe; an old axsim.bat must not select a stale binary.
        simulator=[snapshot_dir/'xsimk.exe']
    elif (snapshot_dir/'axsim.exe').exists():
        simulator=[snapshot_dir/'axsim.exe', '-runall']
    elif (snapshot_dir/'xsimk.exe').exists():
        simulator=[snapshot_dir/'xsimk.exe']
    else:
        raise RuntimeError('Elaboration produced no simulator executable in '+str(snapshot_dir))
    rc,out=command(simulator,build,build/'simulate.log',env=task_env,
                    timeout=600 if ns.test in ('ex8','ex9') else 90)
    print(out)
    passed=('----PASS!!!' in out if ns.test in ('ex8','ex9') else 'PASS ' in out)
    if rc or not passed or 'Fatal:' in out or 'Error!!!' in out:
        raise RuntimeError('Test did not report PASS; see '+str(build/'simulate.log'))

if __name__=='__main__':
    try: main()
    except Exception as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(1)
