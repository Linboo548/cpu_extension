# 修改日志

## 当前进度（2026-10-27）

- I-Cache、D-Cache均已实现，各1 KiB、64行、每行16字节。
- 缓存单测、整机对照、行为回归9/9、真实Xilinx IP回归4/4及模块综合通过。
- UART的50 MHz位流已完成上板测试，9/9通过。
- 待办：位流生成、上板测试。

## 2026-10-27：I-Cache与D-Cache

### 修改

| 文件 | 改动 |
| --- | --- |
| `mycpu_env/myCPU/cpu_sram_cache.v` | 新增共享缓存模块：直接映射、四字回填、有效位与标签、命中/缺失统计 |
| `mycpu_env/myCPU/mycpu_top.v` | 接入I/D缓存，增加`ICACHE_ENABLE`、`DCACHE_ENABLE`，默认均开启；GPIO寄存器旁路，UART访问在缓存前拦截 |
| `mycpu_env/myCPU/IF_stage.v` | 增加取指完成和取消握手，缺失时保持地址，保存分支/异常/ERTN重定向目标 |
| `mycpu_env/myCPU/EXE_stage.v` | 数据缺失时等待完成，再进入MEM；保留异常、ALE和flush门控 |
| `tests/tb_cache.sv` | 新增缓存模块单测 |
| `tests/tb_if_cache.sv` | 新增取指等待和重定向测试 |
| `tests/tb_cache_cpu.sv`、`software/cache_bench.S` | 新增缓存开关整机对照，比较写回结果及外部RAM访问量 |
| `mycpu_env/soc_verify/soc_bram/testbench/mycpu_tb.v`、现有CPU/UART测试台 | 将参数设置移到CPU实例，适配缓存开关和CPU内UART层级 |
| `tools/run_xsim.py` | 增加`cache`、`if_cache`、`cache_cpu`及`--cache`、`--build-root`；自动生成测试镜像，修复模拟器选择和Windows泛型参数引号 |
| `tools/create_project.tcl` | 移除无效板级generic，默认综合预测和I/D缓存开启配置 |
| `README_Cache.md` | 新增设计说明和复现命令 |

本轮缓存硬件修改为myCPU目录内的四个文件；SoC、桥、板级、时钟和XDC保持`10c225e`的状态。

### 设计参数

- I/D各1 KiB，64行直接映射，每行16字节，读缺失顺序回填4个字。
- D-Cache采用写直达、写不分配；写命中按字节使能更新缓存和RAM。
- 复位清除有效位；整行回填完成后置有效位；取消请求会中止回填。
- 标签按实际RAM地址位计算：I侧20位、D侧18位，统一高位地址别名。
- MMIO使用原桥掩码识别：`(addr & 0x1FFF0000) == 0x1FAF0000`。
- 后端为一拍同步SRAM，指令RAM与数据RAM独立。

### 验证结果

| 测试 | 结果 |
| --- | --- |
| 缓存模块单测 | PASS，980 ns；覆盖回填、命中、冲突、复位、字节/半字/字写、写不分配、别名、MMIO和取消 |
| IF定向测试 | PASS，496 ns；覆盖地址保持、预测目标、ID阻塞、分支取消、异常/ERTN和ADEF |
| 整机缓存开关对照 | PASS，617次寄存器写回一致；I-RAM读取708→73，D-RAM读取261→12，MMIO均读取2次 |
| 行为模型ex9 | 缓存开关×预测开关四组，均58/58、Golden Trace及最终PASS |
| 行为模型UART | 缓存开关两组，均完成3帧回显、3次IRQ/ERTN、LED及计数检查 |
| CPU分支基准 | 缓存开关两组，预测开关各51次写回一致，纠错次数42/5 |
| 真实IP ex9 | 预测开/关均58/58和Golden Trace通过，结束时间3606885/3618735 ns |
| 真实IP UART | 预测开/关均通过6帧、6次IRQ/ERTN、ERA及23次私有访问隔离，结束时间69210/69220 ns |
| SoC接口RTL展开 | PASS，0 Error、0 Critical Warning |
| I-Cache模块综合 | 661 LUT、200 FF，分布式RAM，无锁存器 |
| D-Cache模块综合 | 781 LUT、199 FF，分布式RAM，无锁存器 |

分支基准周期：

| 缓存状态 | 预测关闭 | 预测开启 |
| --- | ---: | ---: |
| 关闭 | 265 | 154 |
| 开启 | 290 | 179 |

后端RAM为一拍，冷缺失增加回填周期。20个硬件源文件的SHA-256与真实IP测试快照一致。

### 复现与记录

```powershell
$py = 'D:/Software/Vivado/2023.2/tps/win64/python-3.8.3/python.exe'
& $py tools/run_xsim.py cache
& $py tools/run_xsim.py if_cache
& $py tools/run_xsim.py cache_cpu
& $py tools/run_xsim.py ex9 --cache 1
& $py tools/run_xsim.py ex9 --cache 1 --predictor 0
& $py tools/run_xsim.py soc_uart --cache 1
```

- 完整汇总：`build/cache_20261027/validation_summary.json`
- 行为回归：`build/cache_20261027/behavioral/summary.json`
- 真实IP回归：`build/cache_20261027/real_ip/summary.json`
- 综合报告：`build/cache_20261027/synth/`
- 设计说明：`README_Cache.md`

## 2026-10-26：50 MHz UART位流与上板

### 修改与构建

- 在`IF_stage.v`寄存分支纠错信号和目标，切断ID到指令BRAM的长组合路径，误预测恢复增加一拍。
- 原布局WNS为-6.924 ns；修改后首次布线WNS为-0.180 ns，经过布线后物理优化和TNS清理完成时序收敛。
- 配置：CPU 50 MHz、timer 100 MHz、预测开启、UART分频434、115200/8N1。
- 构建使用独立XDC副本，修复总线端口括号和未使用的时钟约束。
- 功能回归：分支基准51次写回一致，周期223/149；真实IP UART及ex9预测开关配置全部通过。

### 最终结果

| 项目 | 结果 |
| --- | --- |
| 建立时间 | WNS +0.015 ns，TNS 0 |
| 保持时间 | WHS +0.009 ns，THS 0 |
| 脉宽 | WPWS +4.500 ns，TPWS 0 |
| Bitgen | 0 Error、0 Critical Warning |
| 位流大小 | 3,811,159字节 |
| 生成时间 | 2026-10-26 14:44:31，北京时间 |
| 上板 | Type-6，19100号板，9/9通过 |

位流：`build/bitstream/uart_cpu_50mhz_bp1/uart_cpu_50mhz_bp1.bit`

SHA-256：`61e27f3910f4b4edffc8bfe0aa6ed06c64037a5890d029d5ac54b749493b6f4d`

### 上板记录

| 操作 | 回显 | 数码管 | LED |
| --- | --- | --- | --- |
| 复位 | 无数据 | 00 | FFFF |
| 发送41 | 41 | 01 | FFBE |
| 发送42 | 42 | 02 | FFBD |
| 发送7E | 7E | 03 | FF81 |
| 发送00 | 00 | 04 | FFFF |
| 发送FF | FF | 05 | FF00 |
| 发送55 | 55 | 06 | FFAA |
| 连续发送Loongson | 4C 6F 6F 6E 67 73 6F 6E | 0E | FF91 |
| 复位后发送R | 52 | 01 | FFAD |

- 原始49条事件及9项检查：`build/bitstream/uart_cpu_50mhz_bp1/platform/platform_results.json`
- 时序、资源及构建记录：位流同目录下的报告和`build_result.json`。
- 平台流程采用同一会话上传位流并连接开发板，测试结束后断开。

## 2026-10-26：UART迁入myCPU

### 修改

- 新增`mycpu_env/myCPU/cpu_uart_mmio.v`，实现8N1收发、状态寄存器、分频和RX中断。
- `mycpu_top.v`增加RX/TX端口，在CPU内部完成UART地址译码、读数据选择和硬中断0接入。
- SoC与板级保留RX/TX透传，桥恢复RAM/confreg两路结构。
- UART地址为`0x1FAFF100..0x1FAFF11F`，支持`0xBFAF`别名；命中时屏蔽外部数据总线请求。
- `ID_stage.v`、`MEM_stage.v`及顶层将MEM中的load/CSR结果延后至WB前递，缩短RAM读数据到ID分支的路径。
- 板级`btn_step`使用模板值`2'b11`。

### 验证

- 真实IP UART预测开关两组通过：6字符回显、6次IRQ/ERTN、连续帧及显示。
- 每组23次CPU私有UART访问保持内部处理；F0FC/F120边界访问及CR0读写探针通过。
- ex9预测开关两组均58/58、Golden Trace和最终PASS。
- 板级RTL展开通过，UART实例位于`soc_lite/cpu/u_uart`。
- 记录：`build/uart_cpu_integration_20261026/validation_summary.json`。

### 模板核对

- 原工程：`D:/Files/Vivado/computer_organization`，ex7分支，提交`8cd8b90`。
- 原模板的物理RX/TX未接到CPU，confreg的`0x1FAFFF10`用于仿真打印。
- 原模板GPIO汇编仿真通过00、01、5A、A5、80、FF六组拨码输入。
- 核对及GPIO测试：`build/template_audit_20261026/`。
- 收敛源码时归档的脚本和测试：`build/scope_restore_20261026/`。

## 2026-10-25：GPIO位流与上板

### 构建与配置

- 生成`gpio_demo.S`的22字指令镜像，汇编器16项测试通过。
- 修复XDC总线端口括号，设置板级接口空闲电平，增加独立位流构建与报告导出流程。
- 50 MHz首次布局未收敛，随后生成25 MHz、预测关闭的GPIO演示位流。
- 演示配置：CPU 25 MHz、timer 100 MHz、UART分频217。
- 完成演示后，将默认配置恢复为CPU 50 MHz、timer 100 MHz、UART分频434。

### 构建结果

| 项目 | 结果 |
| --- | --- |
| 建立时间 | WNS +3.361 ns，TNS 0 |
| 保持时间 | WHS +0.038 ns，THS 0 |
| 脉宽 | WPWS +4.500 ns，TPWS 0 |
| 资源 | LUT 5671、寄存器8667、BRAM36 320、DSP 8 |
| 位流大小 | 3,727,091字节 |
| 上板 | 19100号板，11/11通过 |

### 上板记录

| 操作 | 结果 |
| --- | --- |
| 初始状态 | 数码管00，LED FF00 |
| DIP0打开 | LED FF01 |
| BTN1按下250 ms | 00→01 |
| BTN1保持1.5 s | 01→02，只计一次 |
| DIP0关闭 | LED FF00 |
| 减法模式按BTN1 | 02→01 |
| BTN2保持500 ms | 01→00 |
| 拨码设为A5 | LED FFA5 |
| 加法模式连续按10次BTN1 | 01至0A |
| RST复位 | 数码管00 |
| 复位后按BTN1 | 00→01 |

- 位流与报告：`build/bitstream/gpio_demo_bp0_25mhz/`
- 上板记录与截图：该目录的`platform/`。
- 位流SHA-256：`01593124a949ddbbf43c8c51543d8d94d2e2c1e456448c252dd41a96bc0e422c`。

## 提交记录

- `195ed98`：合并分支预测验证，四项回归通过。
- `10c225e`：提交UART迁入myCPU、50 MHz取指时序修复及修改日志，共9个文件。
- 本次提交：加入I-Cache、D-Cache、缓存汇编与测试，适配验证工具，整理设计说明和修改日志。
