module alu(
  input  wire [11:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   // 加法操作
wire op_sub;   // 减法操作
wire op_slt;   // 有符号比较，小于置位
wire op_sltu;  // 无符号比较，小于置位
wire op_and;   // 按位与
wire op_nor;   // 按位或非
wire op_or;    // 按位或
wire op_xor;   // 按位异或
wire op_sll;   // 逻辑左移
wire op_srl;   // 逻辑右移选择信号
wire op_sra;   // 算术右移选择信号
wire op_lui;   // 加载高位立即数

// 控制码分解
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32位加法器
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;
//补码加减法运算（加法器）
assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// 加法、减法结果
assign add_sub_result = adder_result;

// 有符号比较结果  如果rj < rk，最低位为1
assign slt_result[31:1] = 31'b0;   //扩充结果
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31]) //src1为负 src2为正
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// 无符号比较结果
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// 按位逻辑运算
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
//右移需要先扩展为64位，如果是算术右移补符号，逻辑右移补0
assign sr64_result =
    {{32{op_sra & alu_src1[31]}}, alu_src1}
    >> alu_src2[4:0];

assign sr_result   = sr64_result[31:0];

// 最终结果多路选择器
assign alu_result =
      ({32{op_add | op_sub}} & add_sub_result)
    | ({32{op_slt         }} & slt_result)
    | ({32{op_sltu        }} & sltu_result)
    | ({32{op_and         }} & and_result)
    | ({32{op_nor         }} & nor_result)
    | ({32{op_or          }} & or_result)
    | ({32{op_xor         }} & xor_result)
    | ({32{op_lui         }} & lui_result)
    | ({32{op_sll         }} & sll_result)
    | ({32{op_srl | op_sra}} & sr_result);
/*前面的各个运算模块其实在硬件上是同时在计算的。
这里利用位与（&）充当了"门卫"：只有当前正在执行的指令（对应的 op_xxx 为 1），其结果才会和全 1 进行与运算被保留下来；
其他不相关的运算结果都会和全 0 进行与运算，被强制过滤成 0。
最后通过位或（|）将所有支路合并。因为除正确结果外其他全为 0，所以最终输出 alu_result 就是所需的那唯一一个正确结果。*/
endmodule
