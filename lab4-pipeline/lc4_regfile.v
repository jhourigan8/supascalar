/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

module lc4_regfile #(parameter n = 16)
   (input  wire         clk,
    input  wire         gwe,
    input  wire         rst,
    input  wire [  2:0] i_rs,      // rs selector
    output wire [n-1:0] o_rs_data, // rs contents
    input  wire [  2:0] i_rt,      // rt selector
    output wire [n-1:0] o_rt_data, // rt contents
    input  wire [  2:0] i_rd,      // rd selector
    input  wire [n-1:0] i_wdata,   // data to write
    input  wire         i_rd_we    // write enable
    );

    wire [n-1:0] reg_out [7:0];
    wire [n-1:0] reg_rs [7:0];
    wire [n-1:0] reg_rt [7:0];
    wire [7:0] one_hot_rd;

    genvar i;
    for (i = 0; i < 8; i=i+1) begin
        // i guess the genvar gets converted to a binary wire. nice!
        assign reg_rs[i] = (i_rs == i) ? reg_out[i] : 16'b0;
        assign reg_rt[i] = (i_rt == i) ? reg_out[i] : 16'b0;
        assign one_hot_rd[i] = (i_rd == i);
        Nbit_reg #(n, 0) register (
            .in(i_wdata),
            .out(reg_out[i]),
            .clk(clk),
            .we(i_rd_we & one_hot_rd[i]),
            .gwe(gwe),
            .rst(rst)
        );
    end

    // dreaming of array reduction operators rn...
    assign o_rs_data = reg_rs[0] | reg_rs[1] | reg_rs[2] | reg_rs[3] | reg_rs[4] | reg_rs[5] | reg_rs[6] | reg_rs[7];
    assign o_rt_data = reg_rt[0] | reg_rt[1] | reg_rt[2] | reg_rt[3] | reg_rt[4] | reg_rt[5] | reg_rt[6] | reg_rt[7];

endmodule
