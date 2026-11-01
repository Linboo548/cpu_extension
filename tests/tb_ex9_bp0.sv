`timescale 1ns/1ps
module tb_ex9_bp0 #(parameter ICACHE_ENABLE=1, parameter DCACHE_ENABLE=1);
    tb_top #(.BR_PREDICT_ENABLE(0), .ICACHE_ENABLE(ICACHE_ENABLE),
             .DCACHE_ENABLE(DCACHE_ENABLE)) u_tb();
endmodule
