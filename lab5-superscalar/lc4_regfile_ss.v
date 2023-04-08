/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

/* 8-register, n-bit register file with
 * four read ports and two write ports
 * to support two pipes.
 * 
 * If both pipes try to write to the
 * same register, pipe B wins.
 * 
 * Inputs should be bypassed to the outputs
 * as needed so the register file returns
 * data that is written immediately
 * rather than only on the next cycle.
 */
module lc4_regfile_ss #(parameter n = 16)
   (input  wire         clk,
    input  wire         gwe,
    input  wire         rst,

    input  wire [  2:0] i_rs_A,      // pipe A: rs selector
    output wire [n-1:0] o_rs_data_A, // pipe A: rs contents
    input  wire [  2:0] i_rt_A,      // pipe A: rt selector
    output wire [n-1:0] o_rt_data_A, // pipe A: rt contents

    input  wire [  2:0] i_rs_B,      // pipe B: rs selector
    output wire [n-1:0] o_rs_data_B, // pipe B: rs contents
    input  wire [  2:0] i_rt_B,      // pipe B: rt selector
    output wire [n-1:0] o_rt_data_B, // pipe B: rt contents

    input  wire [  2:0]  i_rd_A,     // pipe A: rd selector
    input  wire [n-1:0]  i_wdata_A,  // pipe A: data to write
    input  wire          i_rd_we_A,  // pipe A: write enable

    input  wire [  2:0]  i_rd_B,     // pipe B: rd selector
    input  wire [n-1:0]  i_wdata_B,  // pipe B: data to write
    input  wire          i_rd_we_B   // pipe B: write enable
    );

   // establishing a convention: wire_name[0] is for pipe A, wire_name[1] is for pipe B
   wire [n-1:0] reg_out [7:0];
   wire [n-1:0] reg_rs [1:0] [7:0];
   wire [n-1:0] reg_rt [1:0] [7:0];

   genvar i;
   for (i = 0; i < 8; i=i+1) begin
      // i guess the genvar gets converted to a binary wire. nice!
      // write selection
      wire we_A = i_rd_we_A & (i_rd_A == i);
      wire we_B = i_rd_we_B & (i_rd_B == i);
      wire we = we_A | we_B;
      wire [n-1:0] w_data = we_B ? i_wdata_B : i_wdata_A;
      // pipe A
      assign reg_rs[0][i] = (i_rs_A == i) ? (we ? w_data : reg_out[i]) : 16'b0;
      assign reg_rt[0][i] = (i_rt_A == i) ? (we ? w_data : reg_out[i]) : 16'b0;
      // pipe B
      assign reg_rs[1][i] = (i_rs_B == i) ? (we ? w_data : reg_out[i]) : 16'b0;
      assign reg_rt[1][i] = (i_rt_B == i) ? (we ? w_data : reg_out[i]) : 16'b0;
      // regfile
      Nbit_reg #(n, 0) register (
         .in(w_data),
         .out(reg_out[i]),
         .clk(clk),
         .we(we),
         .gwe(gwe),
         .rst(rst)
      );
   end

   // dreaming of array reduction operators rn...
   assign o_rs_data_A = reg_rs[0][0] | reg_rs[0][1] | reg_rs[0][2] | reg_rs[0][3] | reg_rs[0][4] | reg_rs[0][5] | reg_rs[0][6] | reg_rs[0][7];
   assign o_rt_data_A = reg_rt[0][0] | reg_rt[0][1] | reg_rt[0][2] | reg_rt[0][3] | reg_rt[0][4] | reg_rt[0][5] | reg_rt[0][6] | reg_rt[0][7];
   assign o_rs_data_B = reg_rs[1][0] | reg_rs[1][1] | reg_rs[1][2] | reg_rs[1][3] | reg_rs[1][4] | reg_rs[1][5] | reg_rs[1][6] | reg_rs[1][7];
   assign o_rt_data_B = reg_rt[1][0] | reg_rt[1][1] | reg_rt[1][2] | reg_rt[1][3] | reg_rt[1][4] | reg_rt[1][5] | reg_rt[1][6] | reg_rt[1][7];

endmodule
