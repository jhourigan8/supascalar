`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

module lc4_processor(input wire         clk,             // main clock
                     input wire         rst,             // global reset
                     input wire         gwe,             // global we for single-step clock

                     output wire [15:0] o_cur_pc,        // address to read from instruction memory
                     input wire [15:0]  i_cur_insn_A,    // output of instruction memory (pipe A)
                     input wire [15:0]  i_cur_insn_B,    // output of instruction memory (pipe B)

                     output wire [15:0] o_dmem_addr,     // address to read/write from/to data memory
                     input wire [15:0]  i_cur_dmem_data, // contents of o_dmem_addr
                     output wire        o_dmem_we,       // data memory write enable
                     output wire [15:0] o_dmem_towrite,  // data to write to o_dmem_addr if we is set

                     // testbench signals (always emitted from the WB stage)
                     output wire [ 1:0] test_stall_A,        // is this a stall cycle?  (0: no stall,
                     output wire [ 1:0] test_stall_B,        // 1: pipeline stall, 2: branch stall, 3: load stall)

                     output wire [15:0] test_cur_pc_A,       // program counter
                     output wire [15:0] test_cur_pc_B,
                     output wire [15:0] test_cur_insn_A,     // instruction bits
                     output wire [15:0] test_cur_insn_B,
                     output wire        test_regfile_we_A,   // register file write-enable
                     output wire        test_regfile_we_B,
                     output wire [ 2:0] test_regfile_wsel_A, // which register to write
                     output wire [ 2:0] test_regfile_wsel_B,
                     output wire [15:0] test_regfile_data_A, // data to write to register file
                     output wire [15:0] test_regfile_data_B,
                     output wire        test_nzp_we_A,       // nzp register write enable
                     output wire        test_nzp_we_B,
                     output wire [ 2:0] test_nzp_new_bits_A, // new nzp bits
                     output wire [ 2:0] test_nzp_new_bits_B,
                     output wire        test_dmem_we_A,      // data memory write enable
                     output wire        test_dmem_we_B,
                     output wire [15:0] test_dmem_addr_A,    // address to read/write from/to memory
                     output wire [15:0] test_dmem_addr_B,
                     output wire [15:0] test_dmem_data_A,    // data to read/write from/to memory
                     output wire [15:0] test_dmem_data_B,

                     // zedboard switches/display/leds (ignore if you don't want to control these)
                     input  wire [ 7:0] switch_data,         // read on/off status of zedboard's 8 switches
                     output wire [ 7:0] led_data             // set on/off status of zedboard's 8 leds
                     );

   /*** PIPELINE WIRES ***/
   // Pipes A, B = 0, 1
   // Stages fetch, decode, execute, memory, write = 0, 1, 2, 3, 4

   wire        gswitch;                        // is just B halted in decode?
   wire        gstall;                         // are both A and B halted in decode?
   wire        gmispred [1:0];                 // did we mispredict this branch in the execute stage?
   wire [ 4:0] nop [1:0];                      // should this stage take a NOP input? 
   wire [ 4:0] switch [1:0];                   // should this stage take switched input?
   wire [ 4:0] stall [1:0];                    // should this stage take no new input?
   wire [15:0] insn [1:0] [4:0];               // instruction
   wire [15:0] pc [1:0] [4:0];                 // program counter
   wire [15:0] pc_plus_one [1:0] [4:0];        // program counter + 1
   wire [ 2:0] rssel [1:0] [4:0];              // first read register (rs)
   wire [ 2:0] rtsel [1:0] [4:0];              // second read register (rt)
   wire [ 2:0] rdsel [1:0] [4:0];              // write register (rd)
   wire        rs_re [1:0] [4:0];              // does this instruction read from rs?
   wire        rt_re [1:0] [4:0];              // does this instruction read from rt?
   wire        rd_we [1:0] [4:0];              // does this instruction write to rd?
   wire [15:0] rs_data [1:0] [4:0];            // data in rs
   wire [15:0] rt_data [1:0] [4:0];            // data in rt
   wire [15:0] bypassed_rs_data [1:0] [4:0];   // data in rs after any bypassing
   wire [15:0] bypassed_rt_data [1:0] [4:0];   // data in rt after any bypassing
   wire [15:0] alu_res [1:0] [4:0];            // alu result
   wire [15:0] dmem_in [1:0] [4:0];            // dmem in
   wire        dmem_we [1:0] [4:0];            // dmem write enable
   wire [15:0] dmem_addr [1:0] [4:0];          // dmem address
   wire [15:0] dmem_out [1:0] [4:0];           // dmem out
   wire [15:0] wdata [1:0] [4:0];              // data to write
   wire        nzp_we [1:0] [4:0];             // does this instruction write the NZP bits?
   wire        select_pc_plus_one [1:0] [4:0]; // write PC+1 to the regfile?
   wire        is_load [1:0] [4:0];            // is this a load instruction?
   wire        is_store [1:0] [4:0];           // is this a store instruction?
   wire        is_branch [1:0] [4:0];          // is this a branch instruction?
   wire        is_control_insn [1:0] [4:0];    // is this a control instruction (JSR, JSRR, RTI, JMPR, JMP, TRAP)?
   wire [ 1:0] stall_type [1:0] [4:0];         // is this insn a fake NOP due to a stall? if so, why?
   wire [ 2:0] nzp [1:0] [4:0];                // nzp bits in this stage.
   wire        n_in [1:0] [4:0];               // new n bit.
   wire        z_in [1:0] [4:0];               // new z bit.
   wire        p_in [1:0] [4:0];               // new p bit.

   // Pipeline variables: initialize and then simply pass on!
   // switch?
   // stall?
   // Otherwise pass our values along.
   // Initial values represent a NOP flush.
   // TODO: stall logic!!!!

   // Variables initialized in fetch.
   // Edge case: `stall_type` takes the value of `stall` if we stall here instead of some default.
   genvar i;
   for (i = 0; i < 4; i=i+1) begin
      Nbit_reg #(
         16 + 16 + 16 + 2, 
         {16'h0000, 16'h8200, 16'h8201, 2'h2}
      ) pipe_from_fetch (
         .in(
            {insn[i], pc[i], pc_plus_one[i], stall_type[i]}
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
         .in(
            {rssel[i], rtsel[i], rdsel[i], rs_re[i], rt_re[i], rd_we[i], bypassed_rs_data[i], bypassed_rt_data[i], 
             nzp_we[i], select_pc_plus_one[i], is_load[i], is_store[i], is_branch[i], is_control_insn[i]}
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
         .in(alu_res[i]), 
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
         .in(
            {dmem_in[i], dmem_we[i], dmem_addr[i], dmem_out[i], wdata[i], nzp[i], n_in[i], z_in[i], p_in[i]}
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

   assign insn[0][0] = i_cur_insn_A;
   assign insn[1][0] = i_cur_insn_B;
   cla16 pc_inc_A(pc[0][0], 16'b0, 1'b1, pc_plus_one[0][0]);
   assign pc[1][0] = pc_plus_one[0][0];
   cla16 pc_inc_B(pc[1][0], 16'b0, 1'b1, pc_plus_one[1][0]);
   Nbit_reg #(16, 16'h8200) pc_reg (
      .in(mispred ? alu_res[2] : stall ? pc[0][0] : switch ? pc[1][0] : pc_plus_one[1][0]), 
      .out(pc[0][0]), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   // This is a real instruction -> stall_type 0
   assign stall_type[0][0] = 2'b0;
   // Misprediction flush.
   assign stall[0] = mispred ? 2'h2 : 2'h0;

   assign o_cur_pc = pc[0][0];
   
   /*** DECODE ***/

   genvar j;
   for (j = 0; j < 2; j=j+1) begin
      lc4_decoder decoder (
      .insn(insn[j][1]),
      .r1sel(rssel[j][1]),
      .r1re(rs_re[j][1]),
      .r2sel(rtsel[j][1]),
      .r2re(rt_re[j][1]),
      .wsel(rdsel[j][1]),
      .regfile_we(rd_we[j][1]),
      .nzp_we(nzp_we[j][1]),
      .select_pc_plus_one(select_pc_plus_one[j][1]),
      .is_load(is_load[j][1]),
      .is_store(is_store[j][1]),
      .is_branch(is_branch[j][1]),
      .is_control_insn(is_control_insn[j][1])
   );
   end

   lc4_regfile_ss regfile (
      .clk(clk),
      .gwe(gwe),
      .rst(rst),
      .i_rs_A(rssel[0][1]),
      .o_rs_data_A(rs_data[0][1]),
      .i_rt_A(rtsel[0][1]),
      .o_rt_data_A(rt_data[0][1]),
      .i_rs_B(rssel[1][1]),
      .o_rs_data_B(rs_data[1][1]),
      .i_rt_B(rtsel[1][1]),
      .o_rt_data_B(rt_data[1][1]),
      .i_rd_A(rdsel[0][4]),
      .i_wdata_A(wdata[0][4]),
      .i_rd_we_A(rd_we[0][4])
      .i_rd_B(rdsel[1][4]),
      .i_wdata_B(wdata[1][4]),
      .i_rd_we_B(rd_we[1][4])
   );

   // WD bypass handled by the regfile.

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

   genvar j;
   for (j = 0; j < 2; j=j+1) begin
      // Set ppline stuff.
      assign dmem_we[j][3] = is_store[j][3];
      assign dmem_addr[j][3] = (is_load[j][3] | is_store[j][3]) ? alu_res[j][3] : 16'b0;
      assign dmem_out[j][3] = is_store[j][3] ? bypassed_rt_data[j][3] : 16'b0;
      assign dmem_in[j][3] = i_cur_dmem_data;
      assign wdata[j][3] = is_load[j][3] ? dmem_in[j][3] : (select_pc_plus_one[j][3] ? pc_plus_one[j][3] : alu_res[j][3]);

      // No bypass for rs.
      assign bypassed_rs_data[j][3] = rs_data[j][3];
      // WM bypass into rt only for store.
      assign bypassed_rt_data[j][3] = rd_we[j][4] & rtsel[j][3] == rdsel[j][4] ? wdata[j][4] : rt_data[j][3];

      // New nzp bits.
      assign n_in[j][3] = (wdata[j][3][15] == 1'b1);
      assign z_in[j][3] = (wdata[j][3] == 16'b0);
      assign p_in[j][3] = ~n_in[j][3] & ~z_in[j][3];
   end
   // Old nzp values.
   assign nzp[0][3] = nzp_we[1][3] ? {n_in[1][3], z_in[1][3], p_in[1][3]} : nzp[1][3];
   assign nzp[1][3] = nzp_we[0][4] ? {n_in[0][4], z_in[0][4], p_in[0][4]} : nzp[0][4];

   // Dmem outputs.
   assign o_dmem_we = dmem_we[0][3] | dmem_we[1][3];
   assign o_dmem_addr = dmem_we[0][3] ? dmem_addr[0][3] : dmem_addr[1][3];
   assign o_dmem_towrite = dmem_we[0][3] ? dmem_out[0][3] : dmem_out[1][3];

   /*** WRITE ***/

   // Regfile stuff is in decode.

   /*** TESTS ***/

   // Set test wires as described in README.
   assign test_stall_A = stall_type[0][4];
   assign test_cur_pc_A = pc[0][4];
   assign test_cur_insn_A = insn[0][4];
   assign test_regfile_we_A = rd_we[0][4];
   assign test_regfile_wsel_A = rdsel[0][4];
   assign test_regfile_data_A = wdata[0][4];
   assign test_nzp_we_A = nzp_we[0][4];
   assign test_nzp_new_bits_A = {n_in[0][4], z_in[0][4], p_in[0][4]};
   assign test_dmem_we_A = dmem_we[0][4];
   assign test_dmem_addr_A = dmem_addr[0][4];
   assign test_dmem_data_A = is_store[0][4] ? dmem_out[0][4] : (is_load[0][4] ? dmem_in[0][4] : 16'h0000);
   assign test_stall_B = stall_type[1][4];
   assign test_cur_pc_B = pc[1][4];
   assign test_cur_insn_B = insn[1][4];
   assign test_regfile_we_B = rd_we[1][4];
   assign test_regfile_wsel_B = rdsel[1][4];
   assign test_regfile_data_B = wdata[1][4];
   assign test_nzp_we_B = nzp_we[1][4];
   assign test_nzp_new_bits_B = {n_in[1][4], z_in[1][4], p_in[1][4]};
   assign test_dmem_we_B = dmem_we[1][4];
   assign test_dmem_addr_B = dmem_addr[1][4];
   assign test_dmem_data_B = is_store[1][4] ? dmem_out[1][4] : (is_load[1][4] ? dmem_in[1][4] : 16'h0000);

   /* Add $display(...) calls in the always block below to
    * print out debug information at the end of every cycle.
    *
    * You may also use if statements inside the always block
    * to conditionally print out information.
    */
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
      // run it for that many nanoseconds, then set
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
endmodule
