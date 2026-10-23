// [新增] SRAM风格单周期MMIO UART，8位数据/无校验/1停止位（8N1）。
// 地址 1FAFF100..1FAFF11F（BFAFF100别名也有效），UART不使用虚拟打印寄存器。
// +00 DATA：读出RX数据并清RX_VALID；TX_READY=1时写低字节发送。
// +04 STATUS：[0]TX_READY [1]RX_VALID [2]OVERRUN [3]FRAME_ERROR
//             [4]TX_BUSY [5]RX_BUSY；写1清[2]/[3]。
// +08 CTRL：[0]RX_IRQ_ENABLE；IRQ为“RX_VALID且使能”的电平。
// +0C DIV：每比特时钟数，最小4，仅收发空闲时可修改。
// +10 IRQ_PENDING（只读），+14 分支次数，+18 预测错误次数，+1C 标识。
module uart_mmio #(parameter DEFAULT_CLKS_PER_BIT = 434)(
    input wire clk, input wire resetn,
    input wire en, input wire [3:0] we,
    input wire [4:0] addr, input wire [31:0] wdata,
    output reg [31:0] rdata,
    input wire uart_rx, output wire uart_tx, output wire irq,
    input wire [31:0] bp_branch_count, input wire [31:0] bp_miss_count
);
reg [31:0] divider;
reg irq_enable;
reg rx_meta, rx_sync;
reg [7:0] rx_data, rx_shift;
reg rx_valid, overrun, frame_error;
reg tx_busy;
reg [9:0] tx_shift;
reg [3:0] tx_left;
reg [31:0] tx_timer, rx_timer;
reg [2:0] rx_state, rx_bit;
localparam RX_IDLE=0, RX_START=1, RX_DATA=2, RX_STOP=3, RX_RECOVER=4;
wire write_access = en && (|we);
wire read_access = en && !(|we);
wire read_data = read_access && addr[4:2] == 0;
wire write_status = write_access && we[0] && addr[4:2] == 1;
wire tx_start = write_access && we[0] && addr[4:2] == 0 && !tx_busy;
wire rx_complete = rx_state == RX_STOP && rx_timer == 0 && rx_sync;
wire rx_bad_stop = rx_state == RX_STOP && rx_timer == 0 && !rx_sync;
wire [31:0] byte_mask = {{8{we[3]}},{8{we[2]}},{8{we[1]}},{8{we[0]}}};
wire [31:0] next_divider = (divider & ~byte_mask) | (wdata & byte_mask);
assign uart_tx = tx_busy ? tx_shift[0] : 1'b1;
assign irq = irq_enable && rx_valid;

// RX引脚异步于CPU时钟；双触发器同步后才交给采样状态机。
always @(posedge clk) begin
    if (!resetn) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
    else begin rx_meta <= uart_rx; rx_sync <= rx_meta; end
end

always @(posedge clk) begin
    if (!resetn) begin
        divider <= DEFAULT_CLKS_PER_BIT < 4 ? 4 : DEFAULT_CLKS_PER_BIT;
        irq_enable <= 0;
        rdata <= 0;
    end else begin
        if (write_access && we[0] && addr[4:2] == 2)
            irq_enable <= wdata[0];
        if (write_access && addr[4:2] == 3 && !tx_busy && rx_state == RX_IDLE)
            divider <= next_divider < 4 ? 4 : next_divider;
        // 与原同步RAM一样，在请求上升沿寄存读取数据，下一周期供MEM使用。
        if (read_access) begin
            case (addr[4:2])
                0: rdata <= {24'b0, rx_data};
                1: rdata <= {26'b0, (rx_state != RX_IDLE), tx_busy,
                             frame_error, overrun, rx_valid, !tx_busy};
                2: rdata <= {31'b0, irq_enable};
                3: rdata <= divider;
                4: rdata <= {31'b0, irq};
                5: rdata <= bp_branch_count;
                6: rdata <= bp_miss_count;
                7: rdata <= 32'h55415254;
                default: rdata <= 0;
            endcase
        end
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        tx_busy <= 0; tx_shift <= 10'h3ff; tx_left <= 0; tx_timer <= 0;
    end else if (tx_start) begin
        tx_shift <= {1'b1,wdata[7:0],1'b0}; // 从低位依次发起始位、数据、停止位
        tx_left <= 10;
        tx_timer <= divider - 1'b1;
        tx_busy <= 1;
    end else if (tx_busy) begin
        if (tx_timer != 0) tx_timer <= tx_timer - 1'b1;
        else if (tx_left == 1) begin
            tx_busy <= 0;
            tx_left <= 0;
        end else begin
            tx_shift <= {1'b1,tx_shift[9:1]};
            tx_left <= tx_left - 1'b1;
            tx_timer <= divider - 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        rx_state <= RX_IDLE; rx_timer <= 0; rx_bit <= 0; rx_shift <= 0;
    end else begin
        case (rx_state)
            RX_IDLE: if (!rx_sync) begin
                rx_state <= RX_START;
                rx_timer <= (divider >> 1) - 1'b1;
            end
            RX_START: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                else if (!rx_sync) begin // 半位后仍为0才承认起始位，滤掉短毛刺
                    rx_state <= RX_DATA; rx_bit <= 0; rx_timer <= divider - 1'b1;
                end else rx_state <= RX_IDLE;
            RX_DATA: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                else begin
                    rx_shift[rx_bit] <= rx_sync;
                    rx_timer <= divider - 1'b1;
                    if (rx_bit == 7) rx_state <= RX_STOP;
                    else rx_bit <= rx_bit + 1'b1;
                end
            RX_STOP: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                else rx_state <= rx_sync ? RX_IDLE : RX_RECOVER;
            RX_RECOVER: if (rx_sync) rx_state <= RX_IDLE;
            default: rx_state <= RX_IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        rx_data <= 0; rx_valid <= 0; overrun <= 0; frame_error <= 0;
    end else begin
        if (read_data) rx_valid <= 0;
        if (write_status && wdata[2]) overrun <= 0;
        if (write_status && wdata[3]) frame_error <= 0;
        // 新事件优先于软件清除；同时读旧字节、收到新字节时，新字节保留。
        if (rx_complete) begin
            rx_data <= rx_shift;
            rx_valid <= 1;
            if (rx_valid && !read_data) overrun <= 1;
        end
        if (rx_bad_stop) frame_error <= 1;
    end
end
endmodule
