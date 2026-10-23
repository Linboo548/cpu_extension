# [新增] 仅使用副本中的源文件进行综合前RTL层次检查，不做布线或上板。
set task_root [file normalize [file join [file dirname [info script]] ..]]
set cpu [file join $task_root mycpu_env myCPU]
set rtl [file join $task_root mycpu_env soc_verify soc_bram rtl]
set out [file join $task_root build rtl_check]
file mkdir $out
cd $out
create_project -in_memory -part xc7a200tfbg676-1
set_property include_dirs [list $cpu] [current_fileset]
read_verilog [glob [file join $cpu *.v]]
read_verilog [list [file join $rtl soc_lite_top.v] [file join $rtl uart_mmio.v] \
 [file join $rtl BRIDGE bridge_1x2.v] [file join $rtl CONFREG confreg.v]]
read_verilog [file join $task_root tests synth_blackboxes.v]
synth_design -rtl -top soc_lite_top -generic SIMULATION=1 -part xc7a200tfbg676-1
puts "PASS RTL elaboration: independent CPU + predictor + UART + bridge + confreg"
close_design
