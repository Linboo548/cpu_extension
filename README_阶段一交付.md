# 阶段一交接说明：分支预测与外设扩展

> **交接前提：开始这两项新增扩展之前，原工程的 ex9 已经全部测试通过。**
> 本交付是在这个已通过的CPU基础上，增加分支预测和外设功能的**初版代码**。
> 新代码已完成语法检查，但尚未通过功能仿真和联调，不能按最终完成版验收。
> 请两位队友分别按“二、分支预测交接”和“三、外设功能交接”继续，现有初版可作为起点。

## 一、原工程基线：扩展前ex9已通过

### 1. 已经完成的前置工作

在开始本次“分支预测”和“外设功能扩展”之前，原负责人已经完成五级流水线、前递/阻塞、
乘除法，以及此前约定的CSR、异常中断和异常返回扩展，并且**原工程的ex9全部58个测试点通过，最终输出PASS**。
这不是一个仍在等待完成ex9的基础CPU工程。

证据保存在 `baseline/original_ex9_simulate.log`，末尾为：

```text
----[1997435 ns] Number 8'd58 Functional Test Point PASS!!!
==============================================================
Test end!
----PASS!!!
```

`baseline/ex9_golden_trace.txt` 是随此基线保存的ex9参考Trace；
`baseline/original_cpu_sha256.csv` 是开始扩展时原CPU源码的校验清单。

### 2. 请区分两个版本的验证状态

| 版本 | ex9状态 | 含义 |
|---|---|---|
| 扩展前原工程 `D:/cdp_ede_local-master` | **已经通过** | 原负责人完成的基础验收结果，有最终PASS日志 |
| 本目录中增加预测器/UART后的独立副本 | **尚未完成修改后的回归** | 新增代码会影响取指、冲刷、译码和中断接线，需要检查是否破坏原有功能 |

后文的“重跑ex9”均指**新增扩展后的回归测试**，不是否定或重做原负责人已经完成的ex9验收。
原有功能在原版本中通过，不代表加入新逻辑后必然继续通过；后续应以新的完整运行结果为准。

### 3. 交付边界

- 原工程未被修改，本交付仅修改了独立副本。
- `baseline/` 中保存的是原版本的验证证据、校验值和参考Trace，**不是一整套可运行的未修改CPU源码备份**。
  如果需要恢复原版本或逐行比较，请向原负责人索要原工程备份或对应版本。
- `BR_PREDICT_ENABLE=0`只表示关闭新预测器，**不等于恢复原工程**；新的IF/ID总线、纠错路径、UART及桥接改动仍然存在。
- 板卡型号、引脚最终配置、下载和上板实测由用户指定后续处理，本阶段不认定已完成。

## 二、分支预测交接：已做到哪里，后续做什么

**交接结论：预测器及其IF/ID接入的RTL初版已写入，模块与CPU对比测试已编写；目前停在“语法检查通过、功能联调尚未完成”的阶段。**
接手者不必从空白开始实现BTB，但需要审查现有逻辑、运行测试、补齐边界场景并修正发现的问题。

### 1. 目前已经写入的内容

| 文件 | 已写入的逻辑/用途 |
|---|---|
| `mycpu_env/myCPU/branch_predictor.v` | 默认32项直接映射BTB；完整PC标签、目标地址、有效位、条件分支标记和两位饱和计数器；复位和条目更新 |
| `mycpu_env/myCPU/IF_stage.v` | 根据当前IF指令PC查预测器；选择预测nextPC；将预测nextPC与指令、PC、ADEF一起传到ID；接受ID纠错和WB重定向 |
| `mycpu_env/myCPU/ID_stage.v` | 使用原有前递后的操作数判定实际分支；比较实际nextPC与本指令保存的预测nextPC；生成`br_redirect`；在ID实际离开时发送训练信息 |
| `mycpu_env/myCPU/mycpu_head.v` | IF->ID总线由65位扩为97位；分支反馈总线由33位扩为101位，携带纠错和训练字段 |
| `mycpu_env/myCPU/mycpu_top.v` | `BR_PREDICT_ENABLE`参数，以及`bp_branch_count`、`bp_miss_count`输出 |
| `tests/tb_predictor.sv` | 已编写饱和/滞回、标签别名、陈旧条目失效的模块测试；**未运行通过** |
| `software/branch_bench.S`、`tests/tb_cpu_branch.sv` | 已编写预测开/关CPU的写回序列比较与循环周期对比；包含load-use、除法等待、BL/JIRL；**未运行通过** |

当前初版对条件分支使用两位计数器；对B、BL、JIRL在BTB命中后预测跳转。
这是现有实现范围，不包含返回地址栈、复杂历史预测或Cache。

### 2. 接手时必须看懂的接口约定

- `ds_pred_nextpc`：IF为**这条ID指令**选择过的预测nextPC。必须与指令一起保留，不能在阻塞后错配。
- `actual_nextpc`：用实际分支条件计算的正确nextPC；不跳转时为`ds_pc+4`。
- `br_redirect`：上述两个nextPC不相等时，要求IF纠错。预测正确的实际跳转不应冲刷。
- `bp_resolve_valid`：只有ID有效、就绪、EXE可接收，且没有本条异常、ERTN或WB冲刷时才有效，避免同一条阻塞指令反复训练。
- **注意同名变量语义差异：**ID中的`br_taken`仍表示实际跳转；IF当前解包出的`br_taken`对应反馈总线的纠错位，实际语义是`br_redirect`，不是“所有跳转”。
- WB异常/ERTN重定向的优先级必须高于预测和普通纠错。
- 计数器目前在ID解析时更新，不是WB提交计数；异常/冲刷期间的统计口径仍需审查，不能直接当作已提交指令的精确计数。

### 3. 后续工作，按顺序执行

1. **先跑预测器单元测试。**执行`python tools/run_xsim.py predictor`，检查计数器、标签、目标更新和复位；如失败先修模块本身。
2. **再跑CPU等价性与性能测试。**执行`python tools/run_xsim.py cpu_branch`，要求预测开/关的有效寄存器写回序列一致，程序都到达成功路径。
   记录实际周期、分支次数和错误次数；只有测试实测后才能写“性能提高”。
3. **补充边界用例。**现有测试不能代替全覆盖，重点补测：预测跳但实际不跳、预测目标错误、BTB索引冲突、JIRL目标变化、分支依赖前递值、
   load-use阻塞、多周期除法阻塞、阻塞期间不重复训练，以及异常/ERTN与预测错误同时发生的优先级。
4. **做修改后真实IP回归。**使用本文后面的Vivado建工程方法，分别运行`ex9 0`和`ex9 1`；两者都应得到完整58点与最终PASS。
   这里是在检查新增取指/纠错逻辑是否破坏了原来已经通过的异常中断等功能。
5. **保留性能证据与代码说明。**保存一组可复现的循环程序、预测开关配置、波形、统计值和完整日志，说明是否改善、改善多少以及测试条件。
6. **最后再综合和做时序检查。**尚无综合资源或布局布线验收结果；如果新增查表路径影响时序，再根据报告优化，不应先宣称满足时钟要求。

### 4. 该部分何时可以交差

- 新增模块与CPU测试有真实PASS，补充的阻塞/冲刷用例正确。
- 修改后ex9真实IP回归通过，且未通过关闭Trace或改参考答案来掩盖错误。
- 有预测开/关的可复现性能对比；若某用例无收益，也如实记录原因。
- 交回改动文件、必要的总线说明、波形和日志，而不是仅说“代码可以编译”。

## 三、外设功能交接：已做到哪里，后续做什么

**交接结论：原有GPIO的汇编演示已编写；真实UART、MMIO、RX中断及回显程序的初版也已接入SoC。停在“源码/镜像/部分测试平台齐备，但功能和板级验证未完成”的阶段。**
这部分包含“用汇编控制原有外设”和“新增真实串口外设”两项工作，不能只完成LED演示就认定整个外设方向完成。

### 1. 原有外设：已经做了什么

- LED、数码管、拨码开关、按键及消抖硬件主要复用原`confreg.v`，不是本次重新实现了一套GPIO硬件。
- 新增 `software/gpio_demo.S`，并生成同名子目录中的 `.coe/.mif` 等镜像。
- 程序按设计读取开关并显示到LED，使用按键计数、开关bit0选择加/减、另一按键清零，数码管显示计数。
- `board/loongson_remote_top.v`中将两个`touch_btn`接入原`btn_step`通道；信号极性及显示行为仍需结合实际板卡检查。
- **尚无GPIO专用自动测试平台，也未进行GPIO上板演示。**已有程序和镜像不等于按键/显示功能已经实测成功。

### 2. 新增UART：已经做了什么

| 文件 | 已写入的逻辑/用途 |
|---|---|
| `mycpu_env/soc_verify/soc_bram/rtl/uart_mmio.v` | 8N1 TX/RX、RX双触发器同步、单字节接收缓冲、状态/使能/分频寄存器、溢出与帧错标志、RX电平中断 |
| `mycpu_env/soc_verify/soc_bram/rtl/BRIDGE/bridge_1x2.v` | 在原RAM/confreg译码基础上，增加UART地址区间；注册从设备选择以保持原一拍读取时序 |
| `mycpu_env/soc_verify/soc_bram/rtl/soc_lite_top.v` | 实例化UART；连接CPU访存接口；将UART RX请求接入`hw_int_in[0]`；接入预测器统计寄存器 |
| `board/loongson_remote_top.v` | 复用已有`txd/rxd`端口连接UART；仅是接线初版，未核实最终板级约束 |
| `software/uart_irq_echo.S` | 配置EENTRY/ECFG/CRMD/UART中断；ISR读取字符、清RX请求、更新LED/接收计数并回显；最后ERTN返回 |
| `tests/tb_uart.sv` | 已编写UART位流、寄存器、IRQ、溢出、帧错等模块测试；**未运行通过** |
| `tests/tb_soc_uart.sv` | 已编写3字节的CPU端到端中断回显、上下文检查及显示检查；**未运行通过** |

原虚拟UART仍保留给原测试平台打印；新增真实UART是独立模块，不能把原Tcl控制台能打印字符当作新串口已经成功。
完整MMIO地址和寄存器语义在后面的“UART与中断”一节，接手前请先阅读。

### 3. 后续工作，按顺序执行

1. **先隔离预测器影响。**外设负责人单独联调时，建议先使用`BR_PREDICT_ENABLE=0`；如要测试预测关闭的SoC专项平台，需在平台的SoC参数中显式设置，
   当前`tb_soc_uart.sv`默认仍为开启。不要误认为关预测就撤销了全部CPU改动。
2. **验证UART模块。**执行`python tools/run_xsim.py uart`，检查TX/RX引脚的实际8N1位流、读DATA清接收有效、IRQ使能/撤销、溢出、帧错、字节使能和分频设置。
   先修独立模块问题，再接CPU排查，避免一开始把所有问题混在一起。
3. **验证CPU端到端接入。**执行`python tools/run_xsim.py soc_uart`，检查数据读取是否符合同步访存时序，RX请求能否进入CPU，
   ERA/PRMD/CRMD是否正确，读取外设后IRQ是否撤销，ERTN是否返回原程序；最后比较真实TX回显、LED和数码管值。
4. **补充GPIO仿真。**为`gpio_demo.S`增加测试平台：驱动开关、两路按键并等待原消抖时间，检查一次按下只计一次、加减模式、清零、LED及显示寄存器。
   当前交付中没有`tb_gpio.sv`，该项需要接手者补写，不能只重复运行UART测试。
5. **回归原系统。**保留UART空闲且中断默认关闭，重新运行修改后ex9真实IP工程；这一步检查桥接译码、访存时序和新增中断接线没有破坏已通过的原功能。
   GPIO/串口演示有自己的结果判断，不能拿它们的程序镜像与ex9 Golden Trace混用。
6. **再与分支预测合并验证。**两个方向各自调通后，打开预测器重跑串口中断和GPIO程序，检查预测冲刷与外设请求/中断的交互。
7. **最后处理板级工作。**用户已明确板卡和引脚后续再设置：届时核实器件、CPU实际时钟、TX/RX物理连接与电平、约束和复位极性，
   再综合、检查时序、生成bitstream、下载，并用电脑串口工具验证收发和显示。

### 4. 该部分何时可以交差

- 原有外设演示有仿真或按验收要求完成的实际板级操作证据，不能只有汇编源码。
- UART模块及CPU中断回显测试得到真实PASS，收发、请求清除和ERTN均有证据。
- 修改后ex9回归通过；与分支预测合并后的演示也正确。
- 上板若属于最终验收要求，需补真实串口收发、按键/显示的截图或演示及正确约束；本阶段没有这项结果。
- 单字节RX缓冲无FIFO是本初版明确限制，高速连续输入可溢出；是否扩FIFO由后续需求决定，不应默认已经支持。
- 八路硬件中断逐路验证是另一个未完成的专项；这里UART演示只占用第0路，不声称覆盖全部八路。

## 四、两位队友如何分工与合并

| 负责人 | 建议负责范围 | 需要共同约定的接口 |
|---|---|---|
| 分支预测负责人 | `mycpu_env/myCPU/`中的预测器、IF/ID/头文件/顶层，以及`tb_predictor.sv`、`tb_cpu_branch.sv`、`branch_bench.S` | IF/ID与分支反馈总线打包顺序；`BR_PREDICT_ENABLE`；性能计数输出 |
| 外设负责人 | `uart_mmio.v`、桥、SoC、板级顶层、GPIO/串口汇编、UART/SoC/GPIO测试 | CPU统计端口名和宽度、UART MMIO地址、RX IRQ接入第0路、复位/时钟及一拍访存语义 |

- 两人应从**同一份本交付版本**分出各自工作副本或开发分支，不要一人基于原CPU总线、另一人基于新总线开发。
- `mycpu_head.v`、`mycpu_top.v`和SoC接线存在关联；修改端口或总线宽度时先同步，不能只替换单个文件后省略配套改动。
- 新增性能计数输出已经连接到UART MMIO，外设负责人不要直接删掉；如果调整，应与分支预测负责人共同更新两端。
- 原异常/中断功能的基线已经通过；除非新联调有明确证据定位到相关问题，不要以“ex9还没做完”为由重写CSR或整条流水线。
- 谁修改了汇编，谁重新生成对应镜像并一并提交，避免源码和`.coe/.mif`不一致。
- 合并后再次跑完整回归和新增专项测试；一人的单独PASS不能替代合并后的PASS。
- 各自交回：改动文件、运行命令、测试镜像、日志/波形、已通过项目和仍存在的限制。

**两位负责人拿到的都是“初版代码+待验证项”，不是经过功能验证的最终模块；可以在现有初版上修正，不要求先从零重做。**

## 五、目前交付了什么（速查）

| 内容 | 实现状态 | 验证状态 |
|---|---|---|
| 32项BTB、完整PC标签、两位饱和计数器 | RTL初版已写入 | 语法通过，未完成功能仿真 |
| IF预测、ID校验真实nextPC、错误恢复 | RTL初版已写入 | 语法通过，待检查阻塞/异常交互 |
| 可关闭预测、分支/错误次数统计 | 初版已写入 | 待性能与等价性测试 |
| 真实UART 8N1发送/接收 | RTL初版已写入 | 语法通过，待位流验证 |
| UART MMIO、RX中断接硬件中断0 | 初版已写入 | 待端到端IRQ/ERTN验证 |
| GPIO按键计数/开关选加减程序 | 源码和初始化镜像已生成 | 未做硬件运行验证 |
| UART中断回显/LED/计数显示程序 | 源码和初始化镜像已生成 | 未做硬件运行验证 |
| 小型汇编器 | 已实现本交付程序所需指令子集 | 16项编码单元测试通过 |
| 原ex8/ex9程序和ex9参考Trace | 已复制到独立目录 | 原ex9 PASS日志有保存，不能当作修改后PASS |
| 可移植Vivado建工程、仿真脚本 | 已提供 | 尚未成功在当前环境执行完整建工程流程 |

**不包含Cache，不包含已验证的bitstream，不包含已经建好的 `.xpr`。**
通过下述脚本创建本副本自己的 `.xpr`，不要打开D盘原工程来运行这些修改。

## 六、先看哪些文件

- `mycpu_env/myCPU/branch_predictor.v`：新增预测器。
- `mycpu_env/myCPU/IF_stage.v`：预测下一PC、保存预测信息、接受纠错。
- `mycpu_env/myCPU/ID_stage.v`：实际下一PC比较；只在指令真正离开ID时训练一次。
- `mycpu_env/myCPU/mycpu_head.v`：IF->ID为97位；分支反馈总线为101位。
- `mycpu_env/myCPU/mycpu_top.v`：预测开关和性能计数输出。
- `mycpu_env/soc_verify/soc_bram/rtl/uart_mmio.v`：新增真实UART。
- `mycpu_env/soc_verify/soc_bram/rtl/BRIDGE/bridge_1x2.v`：增加UART从设备译码。
- `mycpu_env/soc_verify/soc_bram/rtl/soc_lite_top.v`：接入UART、RX中断、性能计数。
- `board/loongson_remote_top.v`：将已有txd/rxd端口接入UART；连接两个按键。
- `software/*.S`：带注释的演示程序。
- `tests/`：模块、CPU比较和SoC中断回显测试平台。
- `baseline/`：原CPU SHA256清单、原ex9 PASS日志、匹配ex9的Golden Trace。

新增/功能修改处用 `[新增]` / `[修改]` 等注释标识。副本原有GBK文本已机械转换成UTF-8。

## 七、设计约定

### 分支预测

预测器在IF对当前指令PC查表，以预测值选择下一取指PC。该预测nextPC与指令一起进入ID，
发生阻塞时共同保留。ID在`ds_valid && ds_ready_go && es_allowin`、且无异常/返回时，
用前递后的操作数计算真实nextPC，再与保存的预测值比较。

- 预测正确的实际跳转不冲刷。
- 预测跳、实际不跳时，纠正到`PC+4`。
- 目标错误时，纠正到真实目标。
- 发生WB异常/ERTN时，其重定向优先于普通预测纠错。
- BTB带完整PC标签；相同索引的不同PC不会误命中。
- 条件分支用两位计数器；B/BL/JIRL的目标命中后预测跳转。
- `BR_PREDICT_ENABLE=0`关闭预测，保留纠错/统计路径供对比。

### UART与中断

| 地址 | 寄存器 | 说明 |
|---|---|---|
| `0x1FAFF100` | DATA | 写低字节发送；读接收数据并清RX_VALID |
| `0x1FAFF104` | STATUS | bit0 TX_READY；bit1 RX_VALID；bit2溢出；bit3帧错；bit4/5收发忙 |
| `0x1FAFF108` | CTRL | bit0接收中断使能，复位为0 |
| `0x1FAFF10C` | DIV | 每比特CPU时钟数，最小4；空闲时可改 |
| `0x1FAFF110` | IRQ_PENDING | 只读中断请求，不会清接收数据 |
| `0x1FAFF114` | BRANCH_COUNT | 已解析分支次数 |
| `0x1FAFF118` | MISS_COUNT | 预测错误次数 |
| `0x1FAFF11C` | ID | `0x55415254` |

原桥允许的`0xBFAFxxxx`地址别名也可访问。原虚拟UART `0x1FAFFF10`保持原样，仅用于仿真打印。
TX无发送FIFO，程序必须先轮询TX_READY再写DATA；RX有一个字节缓冲，溢出保留最新字节并置标志。
STATUS的bit2/3采用写1清除。RX IRQ是电平请求，读取DATA会清除请求，不能用TICLR清外设中断。

RX IRQ接`hw_int_in[0]`，对应`ECFG.LIE[2]`、`ESTAT.IS[2]`；还需`CRMD.IE=1`。
`uart_irq_echo.S`在处理程序中用SAVE0/1保存临时寄存器，回显字符并更新显示，然后ERTN返回ERA。

## 八、如何在自己的Vivado中继续

建议先解压到短的英文路径，使用Vivado 2023.2，并新开一个Vivado窗口，避免操作原工程。

### 1. 建独立ex9回归工程

在Vivado Tcl Console中，替换下面的解压路径：

```tcl
cd {C:/your/path/cpu_extension_20261022}
set argv {ex9 1}
source tools/create_project.tcl
source tools/run_project.tcl
```

第二个参数`1`为开启预测，`0`为关闭。脚本不覆盖已经存在的同名工程；再次使用时打开其 `.xpr`。
先比较`ex9 0`和`ex9 1`，两者都必须最终输出`Test end!`和`----PASS!!!`。
不能只看到部分测试点PASS就认定完整通过。

`ex8`也可创建，但本阶段没有匹配ex8的Golden，所以脚本将其标为**功能点回归**、关闭Trace比对。
不能把它描述为ex8完整Trace比对通过。

### 2. 跑新增测试平台

在正常的本机命令行中，进入交付目录执行（Python 3）：

```powershell
python tools/run_xsim.py predictor
python tools/run_xsim.py uart
python tools/run_xsim.py cpu_branch
python tools/run_xsim.py soc_uart
```

如Vivado不在默认D盘，添加`--vivado C:/Xilinx/Vivado/2023.2`等实际安装路径。
每项测试有失败检查和仿真时间上限，日志分别在`build/<测试名>/`。

- `predictor`：计数器饱和/滞回、BTB标签别名、陈旧条目失效。
- `uart`：TX/RX位流、中断、读清、溢出、错误停止位、字节使能、分频寄存器。
- `cpu_branch`：同时运行预测开/关CPU，比较寄存器写回序列并检查循环周期是否减少，含load-use和除法等待。
- `soc_uart`：发送3个UART字节，检查3次中断/返回、ERA和IE恢复、TX引脚回显以及LED/数码管值。

**上述脚本的CPU/SoC测试使用 `tests/sim_models.sv` 的BRAM/除法器行为模型，不能替代真实IP回归。**
真实IP应使用前面的Vivado建工程脚本，在副本工程中跑ex9。
`sim_models.sv`和`synth_blackboxes.v`均不得加入最终综合源文件集。

### 3. 生成演示镜像

镜像已随包提供；修改汇编后可重新生成：

```powershell
python tools/assemble.py software/gpio_demo.S --out software/gpio_demo --full
python tools/assemble.py software/uart_irq_echo.S --out software/uart_irq_echo --full
python tools/assemble.py software/branch_bench.S --out software/branch_bench --full
python tools/test_assembler.py
```

小型汇编器只支持演示所需子集和固定双指令li/la，不是完整GNU工具链。
也可以用原LA32R工具链编译，但必须保持程序入口和异常入口地址一致。

演示工程创建时把`set argv {ex9 1}`换为`set argv {gpio_demo 1}`或`{uart_irq_echo 1}`。
它们是演示镜像，**不要使用原ex9的Trace或原功能点计数规则判断演示结果**。

## 九、板卡及尚未验证的事项

- 用户要求板卡后续再设置。本阶段仅保留原xpr的`xc7a200tfbg676-1`，并复制原约束，未确认真实板卡适配。
- 原XDC已有txd=H18、rxd=J20，仅沿用接口，不代表已经核实USB-UART物理连接。
- 原PLL源码配置CPU输出50MHz，UART默认分频434，约115200波特；若之后改变CPU时钟，需同步修改分频。
- 拷贝的远程适配器对拨码和LED有取反逻辑；按键原confreg有较长消抖等待。
- 未做综合资源/布局布线时序验收，未烧录开发板。
- UART是单字节RX缓冲，连续高速输入可能溢出，不承诺无丢字节吞吐。
- 未完成八路硬件中断逐路屏蔽/触发专项测试；本新增演示只使用第0路。

## 十、当前工具限制与真实验证边界

Vivado xvlog已成功解析CPU、预测器、UART、桥、SoC、板级顶层以及新增测试平台。
但XSim在当前受管执行环境启动自带MinGW GCC时失败；尝试使用现有LLVM构建生成的C驱动后，
又遇到仿真内核启动失败或超时。普通Vivado批处理启动也受访问限制。

`tools/run_xsim.py --llvm-fallback`仅保留为本地诊断尝试，**当前并未验证可成功运行**；
正常Vivado安装不需要这个选项。本阶段不修改系统安装，也不绕过权限。

因此当前可以确认的是：**源码已保存、语法通过、汇编器16项单元测试通过、原CPU文件校验未变。**
不能确认修改后的功能仿真通过、预测性能提高、真实串口通信成功或上板通过。

下一阶段从“新增测试实际运行 + 修改后ex9真实IP回归”继续，在现有初版上定位、补测和修正。
再次强调：**原工程在开始这两项扩展前ex9已通过；待完成的是新增两项扩展的验证及其引入改动后的回归。**
