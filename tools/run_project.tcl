# 在已打开的独立Vivado工程中 source 本文件。只运行现有回归镜像ex8/ex9。
set task_root [file normalize [file join [file dirname [info script]] ..]]
set sim_dir [file join [get_property DIRECTORY [current_project]] extension.sim sim_1 behav xsim]
file mkdir $sim_dir
set generic [get_property generic [get_filesets sim_1]]
if {[string match *TRACE_ENABLE=1* $generic]} {
    file copy -force [file join $task_root baseline ex9_golden_trace.txt] [file join $sim_dir golden_trace.txt]
}
launch_simulation
run all
