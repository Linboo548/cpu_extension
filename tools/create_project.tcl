# [新增] 可移植独立工程。用法：Vivado Tcl中 source 本文件；默认ex9。
# batch: vivado -mode batch -source tools/create_project.tcl -tclargs ex9 1
# 镜像：ex9、ex8、gpio_demo、uart_irq_echo、branch_bench；第二参数=预测开关0/1。
set task_root [file normalize [file join [file dirname [info script]] ..]]
set image ex9
set predictor 1
if {[llength $argv] >= 1} {set image [lindex $argv 0]}
if {[llength $argv] >= 2} {set predictor [lindex $argv 1]}
if {$predictor ni {0 1}} {error "predictor must be 0 or 1"}
if {$image ni {ex8 ex9 gpio_demo uart_irq_echo branch_bench}} {error "Unknown image $image"}
if {$image in {ex8 ex9}} {
    set image_dir [file join $task_root for_test_obj ${image}_obj]
} else {
    set image_dir [file join $task_root software $image]
}
foreach init_name {inst_ram.coe data_ram.coe inst_ram.mif data_ram.mif} {
    if {![file exists [file join $image_dir $init_name]]} {error "Missing $init_name; run tools/assemble.py first"}
}
set project_dir [file join $task_root vivado ${image}_bp${predictor}]
# 不使用-force，避免覆盖任何既有工程或用户运行结果。
if {[file exists [file join $project_dir extension.xpr]]} {
    error "Project already exists: $project_dir. Open its extension.xpr instead."
}
# [保留] 原xpr器件。用户要求板卡/引脚后续再设置，当前不据顶层文件名猜测器件。
create_project extension $project_dir -part xc7a200tfbg676-1
set rtl_dir [file join $task_root mycpu_env soc_verify soc_bram rtl]
set cpu_dir [file join $task_root mycpu_env myCPU]
add_files [glob [file join $cpu_dir *.v]]
set_property include_dirs [list $cpu_dir] [get_filesets sources_1]
add_files [list [file join $rtl_dir soc_lite_top.v] [file join $rtl_dir uart_mmio.v] \
    [file join $rtl_dir BRIDGE bridge_1x2.v] [file join $rtl_dir CONFREG confreg.v] \
    [file join $task_root board loongson_remote_top.v] [file join $task_root board remote2local.v]]
# 导入副本中的IP，所有新生成物都属于本工程；绝不打开D盘原工程。
foreach ip_name {inst_ram data_ram clk_pll} {
    import_ip -files [file join $rtl_dir xilinx_ip $ip_name ${ip_name}.xci]
}
foreach ip_name {div_signed div_unsigned} {
    import_ip -files [file join $task_root ip $ip_name ${ip_name}.xci]
}
set_property CONFIG.Coe_File [file join $image_dir inst_ram.coe] [get_ips inst_ram]
set_property CONFIG.Coe_File [file join $image_dir data_ram.coe] [get_ips data_ram]
generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force
set_property top looongson_remote_top [get_filesets sources_1]
set_property generic "BR_PREDICT_ENABLE=$predictor" [get_filesets sources_1]
add_files -fileset constrs_1 [file join $task_root board loongson_remote.xdc]
set tb [file join $task_root mycpu_env soc_verify soc_bram testbench mycpu_tb.v]
add_files -fileset sim_1 $tb
set_property file_type SystemVerilog [get_files $tb]
set_property top tb_top [get_filesets sim_1]
set trace_enabled [expr {$image eq "ex9"}]
set_property generic "BR_PREDICT_ENABLE=$predictor TRACE_ENABLE=$trace_enabled" [get_filesets sim_1]
if {$trace_enabled} {
    add_files -fileset sim_1 [file join $task_root baseline ex9_golden_trace.txt]
    # 在launch_simulation后，把此文件复制到实际运行目录并命名为golden_trace.txt。
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created independent project: [file join $project_dir extension.xpr]"
puts "Image=$image, predictor=$predictor; use tools/run_project.tcl for regression."
