/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

`timescale 1ns / 1ps

// disable implicit wire declaration
`default_nettype none

module lc4_processor
   (input  wire        clk,                // main clock
    input wire         rst, // global reset
    input wire         gwe, // global we for single-step clock
                                    
    output wire [15:0] o_cur_pc, // Address to read from instruction memory
    input wire [15:0]  i_cur_insn, // Output of instruction memory
    output wire [15:0] o_dmem_addr, // Address to read/write from/to data memory
    input wire [15:0]  i_cur_dmem_data, // Output of data memory
    output wire        o_dmem_we, // Data memory write enable
    output wire [15:0] o_dmem_towrite, // Value to write to data memory
   
    output wire [1:0]  test_stall, // Testbench: is this is stall cycle? (don't compare the test values)
    output wire [15:0] test_cur_pc, // Testbench: program counter
    output wire [15:0] test_cur_insn, // Testbench: instruction bits
    output wire        test_regfile_we, // Testbench: register file write enable
    output wire [2:0]  test_regfile_wsel, // Testbench: which register to write in the register file 
    output wire [15:0] test_regfile_data, // Testbench: value to write into the register file
    output wire        test_nzp_we, // Testbench: NZP condition codes write enable
    output wire [2:0]  test_nzp_new_bits, // Testbench: value to write to NZP bits
    output wire        test_dmem_we, // Testbench: data memory write enable
    output wire [15:0] test_dmem_addr, // Testbench: address to read/write memory
    output wire [15:0] test_dmem_data, // Testbench: value read/writen from/to memory

    input wire [7:0]   switch_data, // Current settings of the Zedboard switches
    output wire [7:0]  led_data // Which Zedboard LEDs should be turned on?
    );

   /*** PIPELINE WIRES ***/
   // fetch, decode, execute, memory, write = 0, 1, 2, 3, 4

   wire [ 1:0] stall [3:0];              // should we stall in this stage? if so, why?
   wire [ 3:0] stall_ahead;              // did someone ahead of us stall?
   wire [15:0] insn [4:0];               // instruction
   wire [15:0] pc [4:0];                 // program counter
   wire [15:0] pc_plus_one [4:0];        // program counter + 1
   wire [ 2:0] rssel [4:0];              // first read register (rs)
   wire [ 2:0] rtsel [4:0];              // second read register (rt)
   wire [ 2:0] rdsel [4:0];              // write register (rd)
   wire        rs_re [4:0];              // does this instruction read from rs?
   wire        rt_re [4:0];              // does this instruction read from rt?
   wire        rd_we [4:0];              // does this instruction write to rd?
   wire [15:0] rs_data [4:0];            // data in rs
   wire [15:0] rt_data [4:0];            // data in rt
   wire [15:0] alu_res [4:0];            // alu result
   wire [15:0] dmem_in [4:0];            // dmem in
   wire        dmem_we [4:0];            // dmem write enable
   wire [15:0] dmem_addr [4:0];          // dmem address
   wire [15:0] dmem_out [4:0];           // dmem out
   wire        nzp_we [4:0];             // does this instruction write the NZP bits?
   wire        select_pc_plus_one [4:0]; // write PC+1 to the regfile?
   wire        is_load [4:0];            // is this a load instruction?
   wire        is_store [4:0];           // is this a store instruction?
   wire        is_branch [4:0];          // is this a branch instruction?
   wire        is_control_insn [4:0];    // is this a control instruction (JSR, JSRR, RTI, JMPR, JMP, TRAP)?
   wire [ 1:0] stall_type [4:0];         // is this insn due to a stall? if so, why?

   assign stall_ahead = {1'b0, stall[3], stall[2] | stall[3], stall[1] | stall[2] | stall[3]};

   // if someone ahead stalls, pipe data in a loop.
   // else if i stall, pipe NOP ahead.
   // otherwise pipe along my data.
   // initialize pipe with NOPs
   genvar i;
   for (i = 0; i < 4; i=i+1) begin
      Nbit_reg #(16, 16'h0000) insn_pipe (.in(stall_ahead[i] ? insn[i+1] : stall[i] != 2'h0 ? 16'h0000 : insn[i]), .out(insn[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h8200) pc_pipe (.in(stall_ahead[i] ? pc[i+1] : stall[i] != 2'h0 ? 16'h8200 : pc[i]), .out(pc[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h8201) pc_plus_one_pipe (.in(stall_ahead[i] ? pc_plus_one[i+1] : stall[i] != 2'h0 ? 16'h8201 : pc_plus_one[i]), .out(pc_plus_one[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(3, 3'h0) rssel_pipe (.in(stall_ahead[i] ? rssel[i+1] : stall[i] != 2'h0 ? 3'h0 : rssel[i]), .out(rssel[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(3, 3'h0) rtsel_pipe (.in(stall_ahead[i] ? rtsel[i+1] : stall[i] != 2'h0 ? 3'h0 : rtsel[i]), .out(rtsel[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(3, 3'h0) rdsel_pipe (.in(stall_ahead[i] ? rdsel[i+1] : stall[i] != 2'h0 ? 3'h0 : rdsel[i]), .out(rdsel[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) rs_re_pipe (.in(stall_ahead[i] ? rs_re[i+1] : stall[i] != 2'h0 ? 1'h0 : rs_re[i]), .out(rs_re[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) rt_re_pipe (.in(stall_ahead[i] ? rt_re[i+1] : stall[i] != 2'h0 ? 1'h0 : rt_re[i]), .out(rt_re[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) rd_we_pipe (.in(stall_ahead[i] ? rd_we[i+1] : stall[i] != 2'h0 ? 1'h0 : rd_we[i]), .out(rd_we[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) rs_data_pipe (.in(stall_ahead[i] ? rs_data[i+1] : stall[i] != 2'h0 ? 16'h0000 : rs_data[i]), .out(rs_data[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) rt_data_pipe (.in(stall_ahead[i] ? rt_data[i+1] : stall[i] != 2'h0 ? 16'h0000 : rt_data[i]), .out(rt_data[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) alu_res_pipe (.in(stall_ahead[i] ? alu_res[i+1] : stall[i] != 2'h0 ? 16'h0000 : alu_res[i]), .out(alu_res[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) dmem_in_pipe (.in(stall_ahead[i] ? dmem_in[i+1] : stall[i] != 2'h0 ? 16'h0000 : dmem_in[i]), .out(dmem_in[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) dmem_we_pipe (.in(stall_ahead[i] ? dmem_we[i+1] : stall[i] != 2'h0 ? 1'h0 : dmem_we[i]), .out(dmem_we[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) dmem_addr_pipe (.in(stall_ahead[i] ? dmem_addr[i+1] : stall[i] != 2'h0 ? 16'h0000 : dmem_addr[i]), .out(dmem_addr[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(16, 16'h0000) dmem_out_pipe (.in(stall_ahead[i] ? dmem_out[i+1] : stall[i] != 2'h0 ? 16'h0000 : dmem_out[i]), .out(dmem_out[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) nzp_we_pipe (.in(stall_ahead[i] ? nzp_we[i+1] : stall[i] != 2'h0 ? 1'h0 : nzp_we[i]), .out(nzp_we[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) select_pc_plus_one_pipe (.in(stall_ahead[i] ? select_pc_plus_one[i+1] : stall[i] != 2'h0 ? 1'h0 : select_pc_plus_one[i]), .out(select_pc_plus_one[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) is_load_pipe (.in(stall_ahead[i] ? is_load[i+1] : stall[i] != 2'h0 ? 1'h0 : is_load[i]), .out(is_load[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) is_store_pipe (.in(stall_ahead[i] ? is_store[i+1] : stall[i] != 2'h0 ? 1'h0 : is_store[i]), .out(is_store[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) is_branch_pipe (.in(stall_ahead[i] ? is_branch[i+1] : stall[i] != 2'h0 ? 1'h0 : is_branch[i]), .out(is_branch[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(1, 1'h0) is_control_insn_pipe (.in(stall_ahead[i] ? is_control_insn[i+1] : stall[i] != 2'h0 ? 1'h0 : is_control_insn[i]), .out(is_control_insn[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
      Nbit_reg #(2, 2'h2) stall_type_pipe(.in(stall_ahead[i] ? stall_type[i+1] : stall[i] != 2'h0 ? stall[i] : stall_type[i]), .out(stall_type[i+1]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   end

   /*** FETCH ***/

   assign insn[0] = i_cur_insn;

   wire [15:0] next_pc;

   Nbit_reg #(16, 16'h8200) pc_reg (.in(stall_ahead[0] ? pc[0] : next_pc), .out(pc[0]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   cla16 pc_inc(pc[0], 16'b0, 1'b1, pc_plus_one[0]);

   // never stall at fetch!
   assign stall[0] = 2'b0;
   assign stall_type[0] = 2'b0;

   assign next_pc = pc_plus_one[0];

   assign o_cur_pc = pc[0];
   

   /*** DECODE ***/

   lc4_decoder decoder (
      .insn(insn[1]),
      .r1sel(rssel[1]),
      .r1re(rs_re[1]),
      .r2sel(rtsel[1]),
      .r2re(rt_re[1]),
      .wsel(rdsel[1]),
      .regfile_we(rd_we[1]),
      .nzp_we(nzp_we[1]),
      .select_pc_plus_one(select_pc_plus_one[1]),
      .is_load(is_load[1]),
      .is_store(is_store[1]),
      .is_branch(is_branch[1]),
      .is_control_insn(is_control_insn[1])
   );

   // branch taken flush
   assign stall[1] = 2'b0;

   /*** EXECUTE ***/

   lc4_alu alu (
      .i_insn(insn[2]),
      .i_r1data(
         // MX and WX bypassing into rs
         (rssel[2] == rdsel[3] & rd_we[3]) ? alu_res[3] : 
         (rssel[2] == rdsel[4] & rd_we[4]) ? alu_res[4] :
         rs_data[2]
      ),
      .i_r2data(
         // MX and WX bypassing into rt
         (rtsel[2] == rdsel[3] & rd_we[3]) ? alu_res[3] : 
         (rtsel[2] == rdsel[4] & rd_we[4]) ? alu_res[4] :
         rt_data[2]
      ),
      .i_pc(pc[2]),
      .o_result(alu_res[2])
   );

   // load to use stall
   assign stall[2] = is_load[3] & (rssel[2] == rdsel[3] | rtsel[2] == rdsel[3]) & ~is_store[2] ? 2'b11 : 2'b00;

   /*** MEMORY ***/

   assign dmem_we[3] = is_store[3];
   assign dmem_addr[3] = (is_load[3] | is_store[3]) ? alu_res[3] : 16'b0;
   // WM bypassing into store data
   assign dmem_out[3] = is_store[3] ? (is_load[4] & rtsel[3] == rdsel[4] ? dmem_in[4] : rt_data[3]) : 16'b0;
   assign dmem_in[3] = i_cur_dmem_data;

   assign o_dmem_we = dmem_we[3];
   assign o_dmem_addr = dmem_addr[3];
   assign o_dmem_towrite = dmem_out[3];

   assign stall[3] = 2'b0;

   /*** WRITE ***/

   wire [15:0] wdata;
   assign wdata = is_load[4] ? dmem_in[4] : (select_pc_plus_one[4] ? pc_plus_one[4] : alu_res[4]);

   /*** REGFILE ***/

   wire [15:0] rs_out;
   wire [15:0] rt_out;

   lc4_regfile regfile (
      .clk(clk),
      .gwe(gwe),
      .rst(rst),
      .i_rs(rssel[1]),
      .o_rs_data(rs_out),
      .i_rt(rtsel[1]),
      .o_rt_data(rt_out),
      .i_rd(rdsel[4]),
      .i_wdata(wdata),
      .i_rd_we(rd_we[4])
   );

   // WD bypass into rs
   assign rs_data[1] = (rssel[1] == rdsel[4] & rd_we[4]) ? wdata : rs_out;
   // WD bypass into rt
   assign rt_data[1] = (rtsel[1] == rdsel[4] & rd_we[4]) ? wdata : rt_out;

   /*** NZP ***/

   wire [2:0] nzp;
   wire n_in;
   wire z_in;
   wire p_in;
   assign n_in = (wdata[15] == 1'b1);
   assign z_in = (wdata == 16'b0);
   assign p_in = ~n_in & ~z_in;

   Nbit_reg #(3, 0) nzp_reg (.in({n_in, z_in, p_in}), .out(nzp), .clk(clk), .we(nzp_we[4]), .gwe(gwe), .rst(rst));

   wire nzp_test;
   assign nzp_test = (insn[4][11] & nzp[2]) | (insn[4][10] & nzp[1]) | (insn[4][9] & nzp[0]);

   /*** TESTS ***/

   assign test_stall = stall_type[4];
   assign test_cur_pc = pc[4];
   assign test_cur_insn = insn[4];
   assign test_regfile_we = rd_we[4];
   assign test_regfile_wsel = rdsel[4];
   assign test_regfile_data = wdata;
   assign test_nzp_we = nzp_we[4];
   assign test_nzp_new_bits = {n_in, z_in, p_in};
   assign test_dmem_we = dmem_we[4];
   assign test_dmem_addr = dmem_addr[4];
   assign test_dmem_data = is_store[4] ? dmem_out[4] : dmem_in[4];

`ifndef NDEBUG
   always @(posedge gwe) begin
      // $display("%d %h %h %h %h %h", $time, f_pc, d_pc, e_pc, m_pc, test_cur_pc);
      // if (o_dmem_we)
      //   $display("%d STORE %h <= %h", $time, o_dmem_addr, o_dmem_towrite);

      // Start each $display() format string with a %d argument for time
      // it will make the output easier to read.  Use %b, %h, and %d
      // for binary, hex, and decimal output of additional variables.
      // You do not need to add a \n at the end of your format string.
      // $display("%d ...", $time);

      // Try adding a $display() call that prints out the PCs of
      // each pipeline stage in hex.  Then you can easily look up the
      // instructions in the .asm files in test_data.

      // basic if syntax:
      // if (cond) begin
      //    ...;
      //    ...;
      // end

      // Set a breakpoint on the empty $display() below
      // to step through your pipeline cycle-by-cycle.
      // You'll need to rewind the simulation to start
      // stepping from the beginning.

      // You can also simulate for XXX ns, then set the
      // breakpoint to start stepping midway through the
      // testbench.  Use the $time printouts you added above (!)
      // to figure out when your problem instruction first
      // enters the fetch stage.  Rewind your simulation,
      // run it for that many nano-seconds, then set
      // the breakpoint.

      // In the objects view, you can change the values to
      // hexadecimal by selecting all signals (Ctrl-A),
      // then right-click, and select Radix->Hexadecimal.

      // To see the values of wires within a module, select
      // the module in the hierarchy in the "Scopes" pane.
      // The Objects pane will update to display the wires
      // in that module.

      //$display(); 
   end
`endif
endmodule
