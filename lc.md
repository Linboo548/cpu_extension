# 修改日志

> 当前按“只能改myCPU源码，SoC和板级模板原样”收敛：相对仓库初始提交，代码仅保留mycpu_env/myCPU下3个文件的修改，另外保留本日志。板级、测试及工具的会话改动已撤回并归档到build/scope_restore_20261026/。CPU仍为50 MHz；25 MHz及扩展SoC的测试均属于历史证据，不能代替课程原始模板的合规验证，详情见末节。

## 2026-10-25：Loongson FPGA Cloud Lab GPIO位流生成与上板验证

### 目标

- 为现有 SoC 生成包含 `gpio_demo.S` 的 bitstream。
- 首次使用 `BR_PREDICT_ENABLE=0`，验证云平台拨码、按键、LED 和两位数码管。
- 平台显示Board Type-6；本次`xc7a200tfbg676-1`位流已在19100号板成功加载并运行。

### 已修改

| 文件 | 修改 | 原因 |
| --- | --- | --- |
| `board/loongson_remote.xdc` | 给 `touch_btn[0:3]` 的各位端口名增加 Tcl 花括号 | 避免方括号被解释为 Tcl 命令 |
| `board/loongson_remote.xdc` | 移除未使用的 11.0592 MHz 时钟约束及按钮/备用时钟网络的 `CLOCK_DEDICATED_ROUTE` 设置 | 板载主时钟输入为50 MHz，CPU由PLL生成时钟；按钮为数据或复位输入 |
| `board/loongson_remote_top.v` | 为未使用的 CPLD 串口、SRAM、Flash 和视频接口补明确的空闲值；双向数据总线保持高阻 | 避免综合对未驱动外部控制信号进行任意处理 |
| `tools/build_bitstream.tcl` | 新增独立工程的综合、实现、bitstream 导出及报告保存流程；重复运行时检查 `NEEDS_REFRESH`，重置失败或中断的任务 | 支持复现构建，避免源码变更后误用旧位流；导出前检查内部建立/保持时间是否有负裕量 |
| `lc.md` | 新建本日志 | 记录变更、验证证据与待完成事项 |
| `board/loongson_remote_top.v` | 新增 `UART_CLKS_PER_BIT` 参数并传入 SoC | CPU降频时同步匹配115200波特率 |
| `tools/create_project.tcl` | 新增第三参数25/50 MHz、配置导入PLL的CPU输出、计算UART分频、按频率区分工程目录并使用共享IP缓存 | 保留50 MHz默认配置，同时提供25 MHz平台演示构建 |

### 构建方式

在本工程根目录运行：

```powershell
& 'D:/Software/Vivado/2023.2/bin/vivado.bat' -mode batch -source tools/build_bitstream.tcl -tclargs gpio_demo 0 25
```

- 工程：`vivado/gpio_demo_bp0_25mhz/extension.xpr`
- 已生成位流：`build/bitstream/gpio_demo_bp0_25mhz/gpio_demo_bp0_25mhz.bit`
- 已生成报告：同目录下的 `timing_summary.rpt`、`utilization.rpt`、`drc.rpt`
- 器件配置目前沿用 `xc7a200tfbg676-1`。

### 当前验证结果

- 已找到本机 Vivado，版本输出为 2023.2。
- 已完成板级顶层及约束的静态检查。
- GPIO 程序重新汇编得到 22 个指令字；新生成的四项 `.coe/.mif`、`program.hex`、`symbols.txt` 与现有六个文件的 SHA-256 全部相同。
- 本机运行汇编器 16 项测试，全部通过，退出码 0。
- 独立 Vivado 工程已创建，RAM/PLL/除法器 IP 已生成。
- 首次构建启动综合子任务时，Windows 脚本宿主报告 `Loading your settings failed. (Access is denied.)`。已停止此轮等待，原日志保留为 `build/bitstream/gpio_demo_bp0/vivado_attempt1.log`。
- 按正常本机权限重试后，综合许可证获取成功，子任务正常运行；两套除法器、数据 RAM、指令 RAM 均已完成综合。
- 50 MHz完整 SoC 综合成功：日志汇总为 0 个 Critical Warning、0 个 Error。
- 50 MHz布局估算WNS约-5.5 ns；一轮重布线后中间报告WNS=-5.061 ns、TNS=-9230.069 ns。为转入25 MHz演示构建，主动停止了这轮实现；这是中间结果，不是完整布线后的验收报告，也未上传此配置。
- 25 MHz演示配置：板载输入仍为50 MHz，PLL的CPU输出改25 MHz，timer输出仍100 MHz，UART每比特217个CPU周期。保留原RAM容量和CPU逻辑。
- 尝试将原工程四个IP缓存复制到 `build/ip_cache/`。25 MHz实际构建未命中，四项均重新综合成功；原复制条目多了一层 `2023.2/`，而外部仓库本轮新条目直接写入根目录下的哈希前缀目录，存在目录层级不一致。后续共享缓存以本轮工具实际写入的格式为准。
- 25 MHz完整SoC综合成功：0个Critical Warning、0个Error。
- 25 MHz实现与bitstream生成成功，构建进程退出码0；位流生成时间为2026-10-25 21:05:08（北京时间）。
- Routed时序报告：WNS=+3.361 ns、TNS=0；WHS=+0.038 ns、THS=0；WPWS=+4.500 ns、TPWS=0，失败端点均为0，未约束内部端点为0。
- 时序报告仍提示12个输入、31个输出未指定外部I/O delay；本轮通过的是现有时钟约束下的内部时序检查及GPIO实际操作，不等于完成所有外部接口时序验证。
- Bitgen设计规则检查：0个Error、16个Warning，告警为乘法DSP未充分流水化的优化建议。
- 布线后资源：LUT 5671（4.21%）、寄存器8667（3.22%）、BRAM36 320（87.67%）、DSP 8（1.08%）。
- 位流大小：3,727,091字节。SHA-256：`01593124A949DDBBF43C8C51543D8D94D2E2C1E456448C252DD41A96BC0E422C`。
- 已上传Loongson FPGA Cloud Lab并进入工作区，开发板ID为19100。GPIO汇编程序上板操作通过，见下表。
- 本轮未运行UART收发程序、未验证串口回显、中断或修改后ex9回归，也未验证50 MHz/开启分支预测的上板配置。

### 预期 GPIO 操作

- BTN6：复位。
- DIP0 ON：BTN1 每次按下计数加一；DIP0 OFF：减一。
- BTN2：计数清零。
- DIP0～DIP7：低八位网页 LED 跟随变化。
- 两位数码管显示计数低八位的十六进制值。

### GPIO上板实测结果

平台日期为2026-10-25，使用本次新生成的25 MHz、预测关闭位流。以下数码管值为两位十六进制，LED值按D15到D0排列。

| 检查 | 实测结果 | 结论 |
| --- | --- | --- |
| 初始状态 | 数码管00，LED=FF00 | 通过 |
| 最右侧拨码ON（对应CPU的DIP0） | LED=FF01 | 通过 |
| BTN1按下约250 ms | 数码管00→01 | 通过 |
| BTN1保持约1.5 s | 数码管01→02，只增加一次 | 通过 |
| 最右侧拨码OFF | LED=FF00 | 通过 |
| 减法模式按BTN1 | 数码管02→01 | 通过 |
| BTN2保持约500 ms | 数码管01→00 | 通过 |
| 低八位拨码设A5 | LED=FFA5 | 通过 |
| 加法模式连续按10次BTN1 | 数码管01、02…09、0A | 通过 |
| 操作面板RST开关并释放 | 计数清零，数码管00 | 通过 |
| 复位后再按BTN1 | 数码管00→01 | 通过 |

- 页面最右侧拨码标号为1，对应SoC的bit0；当前ON为加法模式。
- 操作以面板可见RST/CLK标记为准。此次发现页面内部DOM名称`clk`/`rst`与可见用途对调；操作CLK不使CPU复位，操作可见RST会清零并重新执行程序。
- 极短点击未触发清零，保持500 ms后触发成功。一次坐标点击未命中按键，改用控件标识后完成验证；原始观察数据保留，未将未送达的点击当作硬件通过证据。
- 数码管观察按`board/remote2local.v`实际段码解码；保存了原始段掩码和LED图像状态。

### 证据文件

- 构建主日志：`build/bitstream/gpio_demo_bp0_25mhz/vivado.log`
- 平台逐项记录及全部原始观察：`build/bitstream/gpio_demo_bp0_25mhz/platform/platform_results.json`（11项检查通过）
- 连续计数到0A：`build/bitstream/gpio_demo_bp0_25mhz/platform/count_0A.jpg`
- 复位后重新计数到01：`build/bitstream/gpio_demo_bp0_25mhz/platform/after_reset_count_01.jpg`
- 实测面板截图：`build/bitstream/gpio_demo_bp0_25mhz/platform/gpio_verified.png`

实验页面保留在工作区，最后数码管为01，拨码低八位为A5，最右侧拨码ON，BTN1继续加计数、BTN2保持按下可清零。

## 2026-10-25：按用户要求恢复原工程配置

- `tools/create_project.tcl`恢复原来的两个参数（镜像、预测开关），使用源PLL的CPU 50 MHz、timer 100 MHz配置及UART默认分频434；撤回25 MHz选择、频率目录后缀和共享IP缓存配置。
- `tools/build_bitstream.tcl`恢复使用普通工程目录及两个参数，示例命令为`-tclargs gpio_demo 0`。显式拒绝第三个频率参数，避免旧的25 MHz命令被静默解释为50 MHz。
- 建工程脚本默认镜像仍为ex9，默认分支预测开关仍为1；显式GPIO演示命令中的0仍代表关闭预测。
- 原50 MHz工程为`vivado/gpio_demo_bp0/extension.xpr`，其本地PLL仍是CPU 50 MHz、timer 100 MHz，无UART 217分频覆盖，使用顶层默认434。
- 已验证的`vivado/gpio_demo_bp0_25mhz/`工程、25 MHz位流、时序报告、截图与测试记录作为历史演示保留，未覆盖成50 MHz结果。
- 保留板级UART分频参数（默认434）以兼容历史25 MHz工程的显式217覆盖，避免历史工程重建时串口分频与PLL错配。
- 引脚约束修复、外部接口空闲电平及构建报告检查保留。
- 本次只恢复配置，未重新综合或生成50 MHz位流；先前的25 MHz上板通过结果仍只适用于原测试配置。云端已加载的25 MHz位流不会随本地工程配置恢复自动改变。

当前重新构建命令：

```powershell
& 'D:/Software/Vivado/2023.2/bin/vivado.bat' -mode batch -source tools/build_bitstream.tcl -tclargs gpio_demo 0
```

上文含第三参数25的命令属于历史测试过程，当前脚本不再接受该参数；需要复现历史25 MHz演示时应打开其保留的独立工程。

## 2026-10-26：继续完成UART验证（进行中）

本轮保持CPU 50 MHz、timer 100 MHz及UART默认分频434，不降低工程时钟。单独的串口演示构建显式关闭分支预测以隔离外设验证。

### 修改

- `tools/run_xsim.py`：优先识别实际Vivado安装目录及`XILINX_VIVADO`环境变量；兼容本机生成的`axsim.exe`和旧版`xsimk.exe`，消除编译成功后找不到仿真程序的问题。
- `tests/tb_uart.sv`：补充最小分频4、实际50 MHz/115200分频434下的真实引脚全双工收发检查。
- `tests/tb_soc_uart.sv`：增加预测开关参数；检查6字符，其中后三字符00、FF、55连续发送，不等待各自回显或中断返回；验证IRQ、ERA、ERTN、TX位流、LED及计数。
- `MEM_stage.v`、`ID_stage.v`、`mycpu_top.v`：为解决此前50 MHz时序长路径，将MEM中的load/CSR结果等待至WB再前递；MEM前递总线直接输出已寄存的ALU结果，去掉RAM读数据经ID分支直达IF的组合通路。保留更年轻EXE写入覆盖旧MEM依赖的优先级，load仍通过原结果通路写回。代价是依赖MEM load的指令增加等待周期。
- `tools/validate_real_ip.tcl`：新增独立真实Xilinx RAM/除法IP的UART及ex9验证流程，不导入`tests/sim_models.sv`，检查日志中的实际PASS；ex9需完整58点和最终PASS。

### 已得到的实际结果

- UART模块XSim：PASS，覆盖8N1 TX/RX、IRQ、溢出、帧错、字节使能、MMIO及分频4/434全双工；`build/uart/simulate.log`，仿真结束57560 ns。
- SoC模型IP XSim：6字符中断回显与显示PASS，预测开启；`build/soc_uart/simulate.log`，仿真结束68540 ns。
- CPU分支对比：PASS，预测关闭/开启的51次架构写回一致，181/144周期，42/5次预测纠错；`build/cpu_branch/simulate.log`。
- UART汇编重新生成28个指令字；`build/uart_image_check/`的6项镜像/符号文件与`software/uart_irq_echo/`逐项SHA-256完全一致。
- 真实Xilinx IP SoC UART预测关闭：6字符中断回显与显示PASS，仿真结束68530 ns；`build/validation_soc_uart_bp0/simulate.log`及`result.json`。
- 其余真实IP回归及50 MHz串口位流构建正在进行。尚未宣称本轮UART上板通过。

### 平台连接

- 当前工具中没有浏览器自动化插件。Windows自动审批拒绝读取停在无关网页上的Edge完整可访问性树；改为仅通过HTTP访问用户明确指定的实验平台，已成功登录并读取工作区页面。
- 平台密码及登录会话不写入本日志或交付文件。

## 2026-10-26：按“只能修改myCPU”限制收敛

### 最新范围与回退

- 用户明确：SoC及板级模板必须原样，只能修改myCPU源码。本节取代上文的继续集成/上板计划。
- 相对仓库初始提交，代码只保留`mycpu_env/myCPU/ID_stage.v`、`MEM_stage.v`、`mycpu_top.v`的MEM load等待及前递通路调整；`lc.md`按用户先前要求保留。
- `board/loongson_remote.xdc`、`board/loongson_remote_top.v`、`tests/tb_soc_uart.sv`、`tests/tb_uart.sv`、`tools/create_project.tcl`、`tools/run_xsim.py`已全部恢复为仓库初始内容。
- 本轮新增的定向汇编、测试台、测试启动器、位流构建脚本及真实IP验证脚本已移入`build/scope_restore_20261026/`，不再作为工程源码改动。该目录的`manifest.json`记录原文件SHA-256与归档动作；未删除验证结果。
- 独立25 MHz旧工程仍保留为历史产物，但当前板级模板不再含兼容25 MHz的UART分频参数，不能声称它可直接引用当前源码复现。
- 当前50 MHz UART位流构建已主动停止，尚无新位流或上板结果。停止前完整综合成功，布局后的中间时序估算仍约WNS=-4.3 ns，不能视为通过50 MHz时序验收。此前25 MHz云板程序没有被本轮覆盖。
- 平台研究仅进行指定站点HTTP读取及协议握手，没有上传、烧录、串口收发或按键操作。

### 回退前已完成的验证

以下结果验证的是当时的扩展SoC环境。当前myCPU三文件在这些验证之后未再修改；其中六字符测试台和新启动器的确切版本已保存在归档目录，不能把恢复后的旧测试台当作六字符结果来源。

| 验证 | 预测关闭 | 预测开启 | 证据目录 |
| --- | --- | --- | --- |
| 真实Xilinx RAM/除法IP，6字符UART引脚回显、IRQ/ERTN、连续帧及显示 | PASS，68530 ns | PASS，68540 ns | `build/validation_soc_uart_bp0/`、`bp1/` |
| 真实Xilinx IP，ex9 Golden Trace及全部58个测试点、最终PASS | PASS，2006895 ns | PASS，2003075 ns | `build/validation_ex9_bp0/`、`bp1/` |
| 定向load依赖测试，13项内存签名、JIRL链接、错路写入及MMIO检查 | PASS，131周期 | PASS，131周期 | `build/load_forwarding/simulate.log` |

- 四套真实IP验证各有`result.json`和实际`simulate.log`，批处理进程退出码0。
- 定向测试补充覆盖load到分支/JIRL/存储、MMIO读写、字节load，以及更年轻EXE写入覆盖旧MEM load的优先级；其RAM/除法器采用本地行为模型，不能称为真实IP回归。
- 汇编器16项测试全部通过。

### 原始模板仍需确认

- 仓库仅有初始提交`078c978`，该提交已经包含`uart_mmio.v`、SoC UART实例及桥译码，不能据此证明它与课程未修改模板一致。
- 文档记录的原工程`D:/cdp_ede_local-master`目前不存在；已向用户询问课程原始工程/压缩包的本地路径。
- 若课程模板没有连接到CPU的真实UART控制器及物理串口通路，仅修改myCPU源码不能补齐板级串口接线；需要先依据原模板判断可行接口，不能把现有扩展SoC的UART仿真PASS算作满足“模板原样”的验收。

## 2026-10-26：核对用户提供的原始模板

### 来源及原样范围

- 用户提供`D:/Files/Vivado/computer_organization`。原仓库当前为`ex7`分支、提交`8cd8b90`，`experiment.txt`为7，只有ex1～ex7分支。
- 原目录始终只读，未切换分支、改工程或修改源码；核对前后Git工作区均无改动。
- 对照结果保存在`build/template_audit_20261026/comparison.json`：当前扩展工作区的SoC、桥、板级顶层、适配器及XDC与该模板不同；confreg仅行尾不同。因此前节的“只保留myCPU三个文件差异”只针对本仓库初始提交，不能解释为本工作区已与课程原始模板完全一致。

### 串口的实际硬件边界

- 原`mycpu_top.v:1–11`只有时钟、复位、指令/数据SRAM和调试接口，没有串口接口。
- 原`soc_bram/rtl/soc_lite_top.v:67–83`没有UART端口，`:141–162`CPU实例也没有UART连线。
- 原远程`mycpu_env/loongson_remote_top.v:40–41`声明了`txd/rxd`，但`:81–97`没有将它们连到SoC；CPLD串口同样没有实现。引脚约束不会自动建立RTL连接。
- 原`confreg.v:309–328`只提供`0x1FAFFF10`虚拟UART寄存器，供仿真打印，不是真实8N1串行收发器。
- 原远程顶层`:96`将`btn_step`固定为`2'b11`，不能沿用此前修改模板后的BTN1/BTN2计数演示作为原样模板证据。
- 结论：严格只改myCPU、完全不动SoC和板级模板，无法将真实UART接到板上的串口引脚。UART控制器、MMIO拦截和中断可以放在myCPU内，但仍必须让SoC及板级顶层透传RX/TX。
- 仅供审阅的两文件最小接线差异保存在`build/template_audit_20261026/minimal_uart_wiring_proposal.patch`，没有应用。该差异只展示接线，仍需CPU侧UART实现及完整验证，不能当作已完成的串口功能。

### 不改模板的已有外设汇编验证

- 使用原模板全部五个CPU文件（`alu.v`、`divider.v`、`mycpu_top.v`、`regfile.v`、`tools.v`）、原SoC、原桥和原confreg，直接读取原文件编译，未修改或替换其中任何源码。
- 新汇编`build/template_audit_20261026/gpio_strict_template/gpio_poll.S`循环读取`0x1FAFF060`，写入LED的`0x1FAFF020`和数码管数据的`0x1FAFF050`；不依赖模板未接入的按键。
- XSim仿真实际检查拨码00、01、5A、A5、80、FF六组，要求观察到新的有效写入且LED/NUM均与拨码值一致，全部PASS，540 ns结束。
- 日志、镜像、临时测试台及运行脚本均位于`build/template_audit_20261026/gpio_strict_template/`。编译和展开日志无Warning、Critical或Error；`input_sha256.json`记录输入文件，验证前后SHA-256未改变。
- 本次使用本地BRAM行为模型、`SIMULATION=1`。结果证明原模板的已有外设可以由汇编控制，不是实际IP时序或50 MHz上板验收。

### 当前扩展CPU的覆盖兼容性

- 当前扩展CPU并非可直接覆盖到该ex7模板的交付包：EXE依赖模板中没有的`div_signed/div_unsigned` IP；新增`hw_int_in`在原SoC中悬空；原CPU的`tools.v`集中定义译码器，与当前拆分的译码器文件混放会重复定义。
- 本轮没有因此继续扩大源码改动；上述风险需在真正制作CPU覆盖包时于myCPU目录内解决，不能将此前扩展SoC下的ex9 PASS等同于该覆盖包已经通过原模板验证。
- 最新要求状态：第一项已在原模板下通过汇编功能仿真；第二项受“模板原样”的物理连线限制，尚不能完成真实串口上板功能。

## 2026-10-26：经用户授权应用RX/TX最小接线方案

本节为最新状态，取代前节“接线方案未应用”。用户明确回复“应用”，允许SoC和板级透传RX/TX，其余UART逻辑放在myCPU内；修改仍仅发生在`D:/Files/Code/cpu_extension`，原`computer_organization`工程保持只读。

### 已应用的硬件源码

| 文件 | 当前行为 |
| --- | --- |
| `mycpu_env/myCPU/cpu_uart_mmio.v` | 新增CPU内部UART控制器，复用此前8N1收发、状态、分频和RX中断逻辑 |
| `mycpu_env/myCPU/mycpu_top.v` | 新增RX/TX端口；在CPU内部拦截UART寄存器访问、保持一拍读取选择、屏蔽外发请求，并将RX IRQ内部接入CSR硬中断0 |
| `mycpu_env/soc_verify/soc_bram/rtl/soc_lite_top.v` | 恢复用户原模板，只增加RX/TX两端口及CPU实例的对应连线，不再实例化UART |
| `board/loongson_remote_top.v` | 恢复用户原模板，只把原有rxd/txd连接到SoC；原GBK中文注释转为本仓库使用的UTF-8，逻辑没有额外改动 |
| `mycpu_env/soc_verify/soc_bram/rtl/BRIDGE/bridge_1x2.v` | 恢复用户原模板，逐字节一致，移除以前的UART地址译码 |

- UART寄存器仍为`0x1FAFF100..0x1FAFF11F`，兼容原桥允许的`0xBFAF`别名；此前的`software/uart_irq_echo.S`地址和中断配置仍适用。
- UART命中时CPU的外部`data_sram_en`和写字节使能均为0，避免同一个请求继续访问原桥、RAM或confreg。返回选择与UART/同步RAM读数在同一时钟沿寄存，MEM仍按原一拍时序使用。
- UART访问使能来自EXE已经检查过的有效访存请求，保留异常、ERTN、流水线清空和握手对副作用的抑制。
- CPU默认50 MHz、分频434、115200波特、8N1。未接串口输入默认为空闲1，未接外部硬中断默认为0；UART IRQ在CPU内与硬中断0合并。
- 原GPIO/confreg、显示适配逻辑、时钟、RAM和引脚约束没有因本方案新增功能改动。为保持原模板，板级按键仍固定为未按下，未恢复早先的BTN1/BTN2演示接线。
- 旧`rtl/uart_mmio.v`保留供历史材料兼容，但当前SoC和板级层次中没有实例化它；实际使用的模块位于myCPU目录。
- 迁移前文件备份、原模板与应用文件SHA-256见`build/uart_cpu_integration_20261026/pre_apply/`和`template_application.json`。

### 约束范围及验证入口

- `template_scope_checks.json`五项检查全部为true：去掉RX/TX新增行后，SoC和板级与原模板一致；桥逐字节一致；confreg和显示适配器保持原逻辑。编码/行尾差异单独处理，不伪称字节完全一致。
- 为遵守模板范围，SoC及板级不再保留扩展版的预测/分频参数。测试参数在CPU实例设置；本次临时测试台使用CPU层`defparam`，不增加SoC功能。
- 正式`tests/`、`tools/`没有继续扩大改动。其旧入口仍针对此前SoC参数和层级；本次已适配的验证入口为`build/uart_cpu_integration_20261026/validate.tcl`，不要混用旧的SoC层UART测试台。
- 原模板本身没有创建当前CPU使用的外部除法IP；本次验证在本项目内明确导入已有`ip/div_signed`、`div_unsigned`。本次应用不等于把当前CPU直接覆盖到原ex7工程就能自动完成所有构建依赖。

### 已获得的新验证证据

- 真实Xilinx RAM/除法IP串口仿真：预测关闭和开启均PASS，分别68670/68680 ns结束；每套验证6字符回显、6次IRQ/ERTN、连续帧、LED和数码管。
- 每套23次CPU私有UART访问均确认没有外发CPU使能/写使能，没有触发桥conf_en或RAMen；`F0FC`、`F120`两侧边界各2次普通访问正确外发；CR0写入`12345678`在UART别名ID读取前后保持，5项读回探针通过。
- 日志和结果：`build/uart_cpu_integration_20261026/soc_uart_bp0/`、`soc_uart_bp1/`。
- 板级Vivado RTL展开通过，确认存在`soc_lite/cpu/u_uart`、不存在`soc_lite/u_uart`，RX为输入、TX为输出；0个Error、0个Critical Warning。日志为`board_elaboration_batch.log`，结果在`board_elaboration/result.json`。这只是结构检查，不是时序验收。
- 新方案ex9预测关闭、开启均已通过全部58点、Golden Trace及最终PASS，分别2006895/2003075 ns结束；日志和结果在`ex9_bp0/`、`ex9_bp1/`。四套真实IP验证的批处理退出码0，汇总及日志SHA-256见`validation_summary.json`。
- 本轮尚未重新生成bitstream，也没有上传或操作云板。
- 原模板SoC在恢复的桥接连接行保留了一处原有行尾空格；标准`git diff --check`会指出此历史空白。该行与用户原模板一致，未为消除格式提示而扩大模板改动。

复现串口预测关闭验证：

```powershell
& 'D:/Software/Vivado/2023.2/bin/vivado.bat' -mode batch -source build/uart_cpu_integration_20261026/validate.tcl -tclargs soc_uart 0
```

将末两个参数改为`soc_uart 1`、`ex9 0`、`ex9 1`可运行对应验证。

## 2026-10-26：生成新UART位流并上板（已完成）

- 用户明确授权生成新位流及云平台上板测试。继续保留CPU 50 MHz、timer 100 MHz、UART分频434、115200/8N1和默认开启分支预测；不降低CPU时钟。
- 新构建流程及不可变源码快照位于`build/uart_50mhz_20261026/`。直接复用本项目已生成的RAM、PLL和除法器IP产物，不在原`computer_organization`目录生成任何文件。
- 构建单独生成XDC副本：修复四个Tcl总线端口括号，省略未使用备用时钟及未使用网络的路由覆盖；保留原有引脚及50 MHz主时钟。正式XDC源码没有修改。
- `attempt1`实际用于综合的指令/数据RAM MIF与`software/uart_irq_echo/`镜像逐项比较一致（仅统一行尾），证据为`firmware_image_checks.json`，不是只凭文件名判断程序。
- 当前正式源码综合完成，但布局估算WNS=-6.924 ns、TNS=-16480.926 ns；物理优化中间约-6.2 ns。最差路径从乘法DSP结果经ID前递、分支判断/纠错直达大容量指令BRAM使能。为转入修复候选构建，主动停止此轮；这些不是最终布线报告，未生成或上传此配置位流。
- CPU目录内的单文件IF修复位于`mycpu_env/myCPU/IF_stage.v`（原候选为`candidates/IF_stage.v`）：寄存分支纠错信号及目标，保持原训练事件和异常/ERTN优先级；误预测恢复增加一拍。全部功能验证通过后已按相同SHA应用正式源码。
- IF修复分支快测PASS：预测关闭/开启的51项架构写回一致，周期223/149、纠错42/5。真实IP UART/MMIO双配置及ex9双配置也全部通过；ex9仍完整58点、Golden Trace及最终PASS。最终源码IF的SHA-256为`9a202d66c2d3f42553a959a43e022094bb96d74b4f630e7d2099898f06bc1755`，证据为`candidate_validation/validation_summary.json`。
- `attempt2`构建使用该IF的不可变快照，其余代码与当前正式源码一致。首次最终布线仍有WNS=-0.180 ns、TNS=-3.092 ns，32个建立时间失败端点；保持及脉宽已通过，未以此结果上传。
- 平台只读登录正常，Type-6板卡19100空闲；脚本准备检查原始字节、连续字符串、LED/计数及复位后回显，并强制核对待上传位流SHA-256。尚未上传或操作板卡。

### 新位流已生成并通过最终时序

- 对`attempt2/post_route.dcp`执行布线后物理优化及TNS清理，`attempt2_polished`最终时序：WNS=+0.015 ns、TNS=0；WHS=+0.009 ns、THS=0；WPWS=+4.500 ns、TPWS=0，建立/保持/脉宽失败端点全部为0。
- CPU仍50 MHz、timer仍100 MHz、预测开启、UART仍434分频。没有降低频率，也没有加入false-path或multicycle绕过CPU关键路径。
- Bitgen成功，进程退出0，0个Error、0个Critical Warning、16个DSP流水化建议Warning。位流生成时间为2026-10-26 14:44:31（北京时间）。
- 最终文件：`build/bitstream/uart_cpu_50mhz_bp1/uart_cpu_50mhz_bp1.bit`，3,811,159字节。
- SHA-256：`61e27f3910f4b4edffc8bfe0aa6ed06c64037a5890d029d5ac54b749493b6f4d`。
- 导出前已核对bit头中的顶层及器件、最终CPU/timer时钟、全部正式源码与构建快照SHA、复用IP配置及RAM初始化MIF与UART汇编镜像一致。报告和`build_result.json`与位流同目录。
- 只有IF修复应用于正式CPU。另一个EXE乘法等待方案只作为备用候选留在build，其完整回归虽通过，但未应用或用于最终位流；随后中止的追加专项没有计为通过。
- 针对用户再次询问SoC的核对：SoC SHA仍为`19e395b6e7977ea4718990e10193569e03a943f1eb7081bca8a55ba650375373`，与此前授权“应用”RX/TX方案时完全一致；生成位流这一轮没有再改SoC。
- 构建辅助脚本现已包含相同的布线后优化步骤，均仅位于build目录。原始`computer_organization`保持只读。

### 本轮平台测试结果

- 已将通过时序及SHA核对的新位流交给平台实测流程；首次上传收到`./work`确认。
- 客户端随后因页面token为空而在连接板卡前中止，尚未执行串口/复位；首次失败原始证据予以保留，正在核对平台实际分配及Socket.IO登录机制，不将上传确认冒充串口通过。
- 最终已完成同一HTTP会话内的上传及Socket.IO认证，Type-6开发板19100成功运行本次指定SHA位流，测试进程退出0；9/9项硬件检查全部通过。
- 先前两次失败为客户端协议假设：此部署允许空token；重新HTTP登录会丢失上一会话中已上传位流的状态。已按实际网页协议修正，`attempt_01.json`、`attempt_02.json`保留，不计为FPGA功能失败或通过证据。

| 实测项目 | 实际回显 | 数码管 | 远程LED值 | 结果 |
| --- | --- | --- | --- | --- |
| 复位初始状态 | 无数据 | 00 | FFFF | 通过 |
| 字节41（A） | 41 | 01 | FFBE | 通过 |
| 字节42（B） | 42 | 02 | FFBD | 通过 |
| 字节7E（~） | 7E | 03 | FF81 | 通过 |
| 字节00 | 00 | 04 | FFFF | 通过 |
| 字节FF | FF | 05 | FF00 | 通过 |
| 字节55 | 55 | 06 | FFAA | 通过 |
| 连续发送Loongson（8字节） | 4C 6F 6F 6E 67 73 6F 6E | 0E | FF91 | 通过 |
| 复位后发送R | 52 | 01 | FFAD | 通过 |

- 原始TTL接收、LED及数码管段码共49条硬件事件及9项实际检查保存在`build/bitstream/uart_cpu_50mhz_bp1/platform/platform_results.json`。主线程独立核对了全部pass、板号、位流SHA以及当前源码和构建快照一致；`build_result.json`已标记上板测试完成。
- 串口参数为txd/rxd直连、115200、8数据位、无校验、1停止位、无追加换行；此位流运行汇编中断回显程序，接收后回显并更新原SoC的LED和数码管计数。
- 测试结束时最后观察为R、计数01、LED=FFAD。客户端已正常断开，没有保留可操作浏览器页面；开发板后续可能被平台重新分配，复测请重新上传本位流。
- 用户原`D:/Files/Vivado/computer_organization`Git工作区最终复核无改动。
