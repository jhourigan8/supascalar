/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

`timescale 1ns / 1ps

// disable implicit wire declaration
`default_nettype none

module lc4_processor
   (input  wire        clk, // main clock
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
   // Stages fetch, decode, execute, memory, write = 0, 1, 2, 3, 4

   wire [ 1:0] stall [3:0];              // should we stall in this stage? if so, why? (see README)
   wire [ 4:0] pipe_we;                  // is there a stall at or ahead of this pipeline stage?
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
   wire [15:0] bypassed_rs_data [4:0];   // data in rs after any bypassing
   wire [15:0] bypassed_rt_data [4:0];   // data in rt after any bypassing
   wire [15:0] alu_res [4:0];            // alu result
   wire [15:0] dmem_in [4:0];            // dmem in
   wire        dmem_we [4:0];            // dmem write enable
   wire [15:0] dmem_addr [4:0];          // dmem address
   wire [15:0] dmem_out [4:0];           // dmem out
   wire [15:0] wdata [4:0];              // data to write
   wire        nzp_we [4:0];             // does this instruction write the NZP bits?
   wire        select_pc_plus_one [4:0]; // write PC+1 to the regfile?
   wire        is_load [4:0];            // is this a load instruction?
   wire        is_store [4:0];           // is this a store instruction?
   wire        is_branch [4:0];          // is this a branch instruction?
   wire        is_control_insn [4:0];    // is this a control instruction (JSR, JSRR, RTI, JMPR, JMP, TRAP)?
   wire [ 1:0] stall_type [4:0];         // is this insn a fake NOP due to a stall? if so, why?
   wire [ 2:0] nzp [4:0];                // nzp bits in this stage.
   wire        n_in [4:0];                // new n bit.
   wire        z_in [4:0];                // new z bit.
   wire        p_in [4:0];                // new p bit.

   assign pipe_we = {1'b1, stall[3] != 2'h3, stall[2] != 2'h3 & stall[3] != 2'h3, stall[1] != 2'h3 & stall[2] != 2'h3 & stall[3] != 2'h3, stall[0] != 2'h3 & stall[1] != 2'h3 & stall[2] != 2'h3 & stall[3] != 2'h3};

   // Pipeline variables: initialize and then simply pass on!
   // If we are stalling here, pass NOP default values.
   // If there is a stall ahead, keep values ahead the same.
   // Otherwise pass our values along.
   // Initial values represent a NOP flush.

   // Variables initialized in fetch.
   // Edge case: `stall_type` takes the value of `stall` if we stall here instead of some default.
   genvar i;
   for (i = 0; i < 4; i=i+1) begin
      Nbit_reg #(
         16 + 16 + 16 + 2, 
         {16'h0000, 16'h8200, 16'h8201, 2'h2}
      ) pipe_from_fetch (
         .in(pipe_we[i+1] ? 
            (stall[i] != 2'h0 ? 
               {16'h0000, 16'h8200, 16'h8201, stall[i]} : 
               {insn[i], pc[i], pc_plus_one[i], stall_type[i]}) :
            {insn[i+1], pc[i+1], pc_plus_one[i+1], stall_type[i+1]}
         ), 
         .out(
            {insn[i+1], pc[i+1], pc_plus_one[i+1], stall_type[i+1]}),
         .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
      );
   end

   // Variables initialized in decode.
   // Edge case: `rt_data` and `rs_data` are passed different values which are bypassed if needed.
   for (i = 1; i < 4; i=i+1) begin
      Nbit_reg #(
         3 + 3 + 3 + 1 + 1 + 1 + 16 + 16 + 1 + 1 + 1 + 1 + 1 + 1, 
         {3'h0, 3'h0, 3'h0, 1'h0, 1'h0, 1'h0, 16'h0000, 16'h0000, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0}
      ) pipe_from_decode (
         .in(pipe_we[i+1] ? 
            (stall[i] != 2'h0 ? 
               {3'h0, 3'h0, 3'h0, 1'h0, 1'h0, 1'h0, 16'h0000, 16'h0000, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0} : 
               {rssel[i], rtsel[i], rdsel[i], rs_re[i], rt_re[i], rd_we[i], bypassed_rs_data[i], bypassed_rt_data[i], 
                nzp_we[i], select_pc_plus_one[i], is_load[i], is_store[i], is_branch[i], is_control_insn[i]}) :
            {rssel[i+1], rtsel[i+1], rdsel[i+1], rs_re[i+1], rt_re[i+1], rd_we[i+1], bypassed_rs_data[i+1], bypassed_rt_data[i+1], 
             nzp_we[i+1], select_pc_plus_one[i+1], is_load[i+1], is_store[i+1], is_branch[i+1], is_control_insn[i+1]}
         ), 
         .out(
            {rssel[i+1], rtsel[i+1], rdsel[i+1], rs_re[i+1], rt_re[i+1], rd_we[i+1], rs_data[i+1], rt_data[i+1], 
             nzp_we[i+1], select_pc_plus_one[i+1], is_load[i+1], is_store[i+1], is_branch[i+1], is_control_insn[i+1]}),
         .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
      );
   end

   // Variables initialized in execute.
   for (i = 2; i < 4; i=i+1) begin
      Nbit_reg #(16, 16'h0000) pipe_from_execute (
         .in(pipe_we[i+1] ? (stall[i] != 2'h0 ? 16'h0000 : alu_res[i]) : alu_res[i+1]), 
         .out(alu_res[i+1]), 
         .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
      );
   end

   // Variables initialized in memory.
   for (i = 3; i < 4; i=i+1) begin
      Nbit_reg #(
         16 + 1 + 16 + 16 + 16 + 3 + 1 + 1 + 1, 
         {16'h0000, 1'h0, 16'h0000, 16'h0000, 16'h0000, 3'h0, 1'h0, 1'h0, 1'h0}
      ) pipe_from_memory (
         .in(pipe_we[i+1] ? 
            (stall[i] != 2'h0 ? 
               {16'h0000, 1'h0, 16'h0000, 16'h0000, 16'h0000, 3'h0, 1'h0, 1'h0, 1'h0} : 
               {dmem_in[i], dmem_we[i], dmem_addr[i], dmem_out[i], wdata[i], nzp[i], n_in[i], z_in[i], p_in[i]}) :
            {dmem_in[i+1], dmem_we[i+1], dmem_addr[i+1], dmem_out[i+1], wdata[i+1], nzp[i+1], n_in[i+1], z_in[i+1], p_in[i+1]}
         ), 
         .out(
            {dmem_in[i+1], dmem_we[i+1], dmem_addr[i+1], dmem_out[i+1], wdata[i+1], nzp[i+1], n_in[i+1], z_in[i+1], p_in[i+1]}),
         .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
      );
   end

   // Code for each of the 5 stages is below.
   // As boilerplate pipeline code is handled above we just have to do the following in each stage:
   // (1) Initialize modules and registers to compute new values to enter into pipeline
   // (2) Compute any bypasses
   // (3) Compute any stall logic
   // (4) Set any relevant output values

   /*** FETCH ***/

   assign insn[0] = i_cur_insn;
   wire [15:0] next_pc;
   cla16 pc_inc(pc[0], 16'b0, 1'b1, pc_plus_one[0]);
   assign next_pc = pc_plus_one[0];
   Nbit_reg #(16, 16'h8200) pc_reg (.in(mispred ? alu_res[2] : (pipe_we[0] ? next_pc : pc[0])), .out(pc[0]), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   // This is a real instruction -> stall_type 0
   assign stall_type[0] = 2'b0;
   // Misprediction flush.
   assign stall[0] = mispred ? 2'h2 : 2'h0;

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

   lc4_regfile regfile (
      .clk(clk),
      .gwe(gwe),
      .rst(rst),
      .i_rs(rssel[1]),
      .o_rs_data(rs_data[1]),
      .i_rt(rtsel[1]),
      .o_rt_data(rt_data[1]),
      .i_rd(rdsel[4]),
      .i_wdata(wdata[4]),
      .i_rd_we(rd_we[4])
   );

   // WD bypass into rs.
   assign bypassed_rs_data[1] = (rssel[1] == rdsel[4] & rd_we[4]) ? wdata[4] : rs_data[1];
   // WD bypass into rt.
   assign bypassed_rt_data[1] = (rtsel[1] == rdsel[4] & rd_we[4]) ? wdata[4] : rt_data[1];

   // Misprediction flush.
   assign stall[1] = mispred ? 2'h2 : 2'h0;

   /*** EXECUTE ***/

   // What the nzp bits would be here.
   wire [2:0] nzp2 = stall_type[3] == 2'h2 ? (nzp_we[4] ? {n_in[4], z_in[4], p_in[4]} : nzp[4]) : (nzp_we[3] ? {n_in[3], z_in[3], p_in[3]} : nzp[3]);
   // Check if we mispredicted.
   wire mispred;
   assign mispred = is_control_insn[2] | (is_branch[2] & ((insn[2][11] & nzp2[2]) | (insn[2][10] & nzp2[1]) | (insn[2][9] & nzp2[0])));

   lc4_alu alu (
      .i_insn(insn[2]),
      .i_r1data(bypassed_rs_data[2]),
      .i_r2data(bypassed_rt_data[2]),
      .i_pc(pc[2]),
      .o_result(alu_res[2])
   );

   // MX and WX bypass into rs.
   assign bypassed_rs_data[2] = 
      (rssel[2] == rdsel[3] & rd_we[3]) ? wdata[3] : 
      (rssel[2] == rdsel[4] & rd_we[4]) ? wdata[4] :
      rs_data[2];

   // MX and WX bypass into rt.
   assign bypassed_rt_data[2] = 
      (rtsel[2] == rdsel[3] & rd_we[3]) ? wdata[3] : 
      (rtsel[2] == rdsel[4] & rd_we[4]) ? wdata[4] :
      rt_data[2];

   // Load to use stall. Includes stalling for branch decision.
   assign stall[2] = is_load[3] & ((rs_re[2] & rssel[2] == rdsel[3]) | (rt_re[2] & rtsel[2] == rdsel[3] & ~is_store[2]) | is_branch[2]) ? 2'b11 : 2'b00;

   /*** MEMORY ***/

   assign dmem_we[3] = is_store[3];
   assign dmem_addr[3] = (is_load[3] | is_store[3]) ? alu_res[3] : 16'b0;
   assign dmem_out[3] = is_store[3] ? bypassed_rt_data[3] : 16'b0;
   assign dmem_in[3] = i_cur_dmem_data;
   assign wdata[3] = is_load[3] ? dmem_in[3] : (select_pc_plus_one[3] ? pc_plus_one[3] : alu_res[3]);

   // No bypass for rs.
   assign bypassed_rs_data[3] = rs_data[3];
   // WM bypass into rt only for store.
   assign bypassed_rt_data[3] = rd_we[4] & rtsel[3] == rdsel[4] ? wdata[4] : rt_data[3];

   assign stall[3] = 2'b0;

   assign o_dmem_we = dmem_we[3];
   assign o_dmem_addr = dmem_addr[3];
   assign o_dmem_towrite = dmem_out[3];

   // New nzp bits
   assign n_in[3] = (wdata[3][15] == 1'b1);
   assign z_in[3] = (wdata[3] == 16'b0);
   assign p_in[3] = ~n_in[3] & ~z_in[3];
   // Old nzp value
   assign nzp[3] = nzp_we[4] ? {n_in[4], z_in[4], p_in[4]} : nzp[4];

   /*** WRITE ***/

   // Regfile stuff is in decode.

   /*** TESTS ***/

   // Set test wires as described in README.
   assign test_stall = stall_type[4];
   assign test_cur_pc = pc[4];
   assign test_cur_insn = insn[4];
   assign test_regfile_we = rd_we[4];
   assign test_regfile_wsel = rdsel[4];
   assign test_regfile_data = wdata[4];
   assign test_nzp_we = nzp_we[4];
   assign test_nzp_new_bits = {n_in[4], z_in[4], p_in[4]};
   assign test_dmem_we = dmem_we[4];
   assign test_dmem_addr = dmem_addr[4];
   assign test_dmem_data = is_store[4] ? dmem_out[4] : (is_load[4] ? dmem_in[4] : 16'h0000);

`ifndef NDEBUG
   always @(posedge gwe) begin
      if ($time < 16'd2000)
         $display("--------------------------------------------------------------");
      if ($time < 16'd2000)
         $display("insn          %h %h %h %h %h", insn[0], insn[1], insn[2], insn[3], insn[4]);
      if ($time < 16'd2000)
         $display("rs_data       %h %h %h %h %h", rs_data[0], rs_data[1], rs_data[2], rs_data[3], rs_data[4]);
      if ($time < 16'd2000)
         $display("rt_data       %h %h %h %h %h", rt_data[0], rt_data[1], rt_data[2], rt_data[3], rt_data[4]);
      if ($time < 16'd2000)
         $display("wdata         %h %h %h %h %h", wdata[0], wdata[1], wdata[2], wdata[3], wdata[4]);
      if ($time < 16'd2000)
         $display("rssel         %h    %h    %h    %h    %h", rssel[0], rssel[1], rssel[2], rssel[3], rssel[4]);
      if ($time < 16'd2000)
         $display("rtsel         %h    %h    %h    %h    %h", rtsel[0], rtsel[1], rtsel[2], rtsel[3], rtsel[4]);
      if ($time < 16'd2000)
         $display("rdsel         %h    %h    %h    %h    %h", rdsel[0], rdsel[1], rdsel[2], rdsel[3], rdsel[4]);
      if ($time < 16'd2000)
         $display("stall         %h    %h    %h    %h", stall[0], stall[1], stall[2], stall[3]);
      if ($time < 16'd2000)
         $display("stall_type    %h    %h    %h    %h    %h", stall_type[0], stall_type[1], stall_type[2], stall_type[3], stall_type[4]);
      if ($time < 16'd2000)
         $display("pipe_we       %h    %h    %h    %h    %h", pipe_we[0], pipe_we[1], pipe_we[2], pipe_we[3], pipe_we[4]);
      if ($time < 16'd2000)
         $display("dmem_addr     %h %h %h %h %h", dmem_addr[0], dmem_addr[1], dmem_addr[2], dmem_addr[3], dmem_addr[4]);
      if ($time < 16'd2000)
         $display("dmem_in       %h %h %h %h %h", dmem_in[0], dmem_in[1], dmem_in[2], dmem_in[3], dmem_in[4]);
      if ($time < 16'd2000)
         $display("dmem_out      %h %h %h %h %h", dmem_out[0], dmem_out[1], dmem_out[2], dmem_out[3], dmem_out[4]);
      if ($time < 16'd2000)
         $display("alu_res       %h %h %h %h %h", alu_res[0], alu_res[1], alu_res[2], alu_res[3], alu_res[4]);
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
