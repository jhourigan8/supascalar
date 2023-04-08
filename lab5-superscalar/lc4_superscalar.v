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

   // Stall logic! 
   // In priority order, i.e. flush overrides stall overrides switch.
   // 0 = no flush, 1 = superscalar, 2 = mispred, 3 = load to use

   wire        gmispred [1:0];                 // did we mispredict this branch in the execute stage?
   wire [ 1:0] gstall;                         // are both A and B halted in decode and why?
   wire [ 1:0] gswitch;                        // is just B halted in decode and why?
   wire [ 1:0] flush [1:0] [4:0];              // should this stage take a NOP flush input and why?
   wire [ 4:0] stall [1:0];                    // should this stage take no new input? 
   wire [ 4:0] switch [1:0];                   // should this stage take switched input?
   
   assign flush[0][0] = 2'h0;
   assign flush[0][1] = (gmispred[0] | gmispred[1]) ? 2'h2 : 2'h0;
   assign flush[0][2] = (gmispred[0] | gmispred[1]) ? 2'h2 : (gstall != 2'h0) ? gstall : 2'h0;
   assign flush[0][3] = 2'h0; 
   assign flush[0][4] = 2'h0;
   assign flush[1][0] = 2'h0;
   assign flush[1][1] = (gmispred[0] | gmispred[1]) ? 2'h2 : 2'h0;
   assign flush[1][2] = (gmispred[0] | gmispred[1]) ? 2'h2 : (gstall != 2'h0) ? gstall : (gswitch != 2'h0) ? gswitch : 2'h0;
   assign flush[1][3] = gmispred[0] ? 2'h2 : 2'h0; 
   assign flush[1][4] = 2'h0;
   assign stall[0] = {1'b0, 1'b0, 1'b0, gstall != 2'h0, gstall != 2'h0};
   assign stall[1] = {1'b0, 1'b0, 1'b0, gstall != 2'h0, gstall != 2'h0};
   assign switch[0] = {1'b0, 1'b0, 1'b0, gswitch != 2'h0, gswitch != 2'h0};
   assign switch[1] = {1'b0, 1'b0, 1'b0, gswitch != 2'h0, gswitch != 2'h0};

   // Pipeline variables: initialize and then simply pass on!
   // switch?
   // stall?
   // Otherwise pass our values along.
   // Initial values represent a NOP flush.
   // TODO: stall logic!!!!

   // Variables initialized in fetch.
   // Edge case: `stall_type` takes the value of `stall` if we stall here instead of some default.
   genvar j;
   for (j = 0; j < 2; j=j+1) begin
      integer swj = j ? 0 : 1;
      genvar i;
      for (i = 0; i < 4; i=i+1) begin
         integer swi = j ? i : i+1;
         Nbit_reg #(
            16 + 16 + 16 + 2, 
            {16'h0000, 16'h8200, 16'h8201, 2'h2}
         ) pipe_from_fetch (
            .in(
               (flush[j][i+1] != 2'h0) ? {16'h0000, 16'h8200, 16'h8201, flush[j][i+1]} :
               stall[j][i+1] ? {insn[j][i+1], pc[j][i+1], pc_plus_one[j][i+1], stall_type[j][i+1]} :
               switch[j][i+1] ? {insn[swj][swi], pc[swj][swi], pc_plus_one[swj][swi], stall_type[swj][swi]} :
               {insn[j][i], pc[j][i], pc_plus_one[j][i], stall_type[j][i]}
            ), 
            .out(
               {insn[j][i+1], pc[j][i+1], pc_plus_one[j][i+1], stall_type[j][i+1]}),
            .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
         );
      end

      // Variables initialized in decode.
      // Edge case: `rt_data` and `rs_data` are passed different values which are bypassed if needed.
      for (i = 1; i < 4; i=i+1) begin
         integer swi = j ? i+1 : i;
         Nbit_reg #(
            3 + 3 + 3 + 1 + 1 + 1 + 16 + 16 + 1 + 1 + 1 + 1 + 1 + 1, 
            {3'h0, 3'h0, 3'h0, 1'h0, 1'h0, 1'h0, 16'h0000, 16'h0000, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0}
         ) pipe_from_decode (
            .in(
               (flush[j][i+1] != 2'h0) ? {3'h0, 3'h0, 3'h0, 1'h0, 1'h0, 1'h0, 16'h0000, 16'h0000, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0, 1'h0} :
               stall[j][i+1] ? {rssel[j][i+1], rtsel[j][i+1], rdsel[j][i+1], rs_re[j][i+1], rt_re[j][i+1], rd_we[j][i+1], rs_data[j][i+1], rt_data[j][i+1], 
                  nzp_we[j][i+1], select_pc_plus_one[j][i+1], is_load[j][i+1], is_store[j][i+1], is_branch[j][i+1], is_control_insn[j][i+1]} :
               switch[j][i+1] ? {rssel[swj][swi], rtsel[swj][swi], rdsel[swj][swi], rs_re[swj][swi], rt_re[swj][swi], rd_we[swj][swi], bypassed_rs_data[swj][swi], bypassed_rt_data[swj][swi], 
                  nzp_we[swj][swi], select_pc_plus_one[swj][swi], is_load[swj][swi], is_store[swj][swi], is_branch[swj][swi], is_control_insn[swj][swi]} :
               {rssel[j][i], rtsel[j][i], rdsel[j][i], rs_re[j][i], rt_re[j][i], rd_we[j][i], bypassed_rs_data[j][i], bypassed_rt_data[j][i], 
                  nzp_we[j][i], select_pc_plus_one[j][i], is_load[j][i], is_store[j][i], is_branch[j][i], is_control_insn[j][i]}
            ), 
            .out(
               {rssel[j][i+1], rtsel[j][i+1], rdsel[j][i+1], rs_re[j][i+1], rt_re[j][i+1], rd_we[j][i+1], rs_data[j][i+1], rt_data[j][i+1], 
                  nzp_we[j][i+1], select_pc_plus_one[j][i+1], is_load[j][i+1], is_store[j][i+1], is_branch[j][i+1], is_control_insn[j][i+1]}),
            .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
         );
      end

      // Variables initialized in execute.
      for (i = 2; i < 4; i=i+1) begin
         integer swi = j ? i+1 : i;
         Nbit_reg #(16, 16'h0000) pipe_from_execute (
            .in(
               (flush[j][i+1] != 2'h0) ? 16'h0000 :
               stall[j][i+1] ? alu_res[j][i+1] :
               switch[j][i+1] ? alu_res[swj][swi] :
               alu_res[j][i]
            ), 
            .out(alu_res[j][i+1]), 
            .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
         );
      end

      // Variables initialized in memory.
      for (i = 3; i < 4; i=i+1) begin
         integer swi = j ? i+1 : i;
         Nbit_reg #(
            16 + 1 + 16 + 16 + 16 + 3 + 1 + 1 + 1, 
            {16'h0000, 1'h0, 16'h0000, 16'h0000, 16'h0000, 3'h0, 1'h0, 1'h0, 1'h0}
         ) pipe_from_memory (
            .in(
               (flush[j][i+1] != 2'h0) ? {16'h0000, 1'h0, 16'h0000, 16'h0000, 16'h0000, 3'h0, 1'h0, 1'h0, 1'h0} :
               stall[j][i+1] ? {dmem_in[j][i+1], dmem_we[j][i+1], dmem_addr[j][i+1], dmem_out[j][i+1], wdata[j][i+1], nzp[j][i+1], n_in[j][i+1], z_in[j][i+1], p_in[j][i+1]} :
               switch[j][i+1] ? {dmem_in[swj][swi], dmem_we[swj][swi], dmem_addr[swj][swi], dmem_out[swj][swi], wdata[swj][swi], nzp[swj][swi], n_in[swj][swi], z_in[swj][swi], p_in[swj][swi]} :
               {dmem_in[j][i], dmem_we[j][i], dmem_addr[j][i], dmem_out[j][i], wdata[j][i], nzp[j][i], n_in[j][i], z_in[j][i], p_in[j][i]}
            ), 
            .out(
               {dmem_in[j][i+1], dmem_we[j][i+1], dmem_addr[j][i+1], dmem_out[j][i+1], wdata[j][i+1], nzp[j][i+1], n_in[j][i+1], z_in[j][i+1], p_in[j][i+1]}),
            .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst)
         );
      end
   end

   // Code for each of the 5 stages is below.
   // As boilerplate pipeline code is handled above we just have to do the following in each stage:
   // (1) Initialize modules and registers to compute new values to enter into pipeline
   // (2) Compute any bypasses
   // (3) Compute any stall logic
   // (4) Set any relevant output values

   /*** FETCH ***/

   // Set insn and pc pipeline values
   assign insn[0][0] = i_cur_insn_A;
   assign insn[1][0] = i_cur_insn_B;
   cla16 pc_inc_A(pc[0][0], 16'b0, 1'b1, pc_plus_one[0][0]);
   assign pc[1][0] = pc_plus_one[0][0];
   cla16 pc_inc_B(pc[1][0], 16'b0, 1'b1, pc_plus_one[1][0]);

   // Next PC priority order: mispred A, mispred B, stall, switch, default
   Nbit_reg #(16, 16'h8200) pc_reg (
      .in(
         gmispred[0] ? alu_res[0][2] : 
         gmispred[1] ? alu_res[1][2] :
         gstall ? pc[0][0] : 
         gswitch ? pc[1][0] : 
         pc_plus_one[1][0]
      ), 
      .out(pc[0][0]), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   // Real instructions -> default stall_type 0
   assign stall_type[0][0] = 2'h0;
   assign stall_type[1][0] = 2'h0;

   assign o_cur_pc = pc[0][0];
   
   /*** DECODE ***/

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
      .i_rd_we_A(rd_we[0][4]),
      .i_rd_B(rdsel[1][4]),
      .i_wdata_B(wdata[1][4]),
      .i_rd_we_B(rd_we[1][4])
   );

   // WD bypass handled by the regfile.
   for (j = 0; j < 2; j=j+1) begin
      assign bypassed_rs_data[j][1] = rs_data[j][1];
      assign bypassed_rt_data[j][1] = rt_data[j][1];
   end

   // Full stall: D.A load to use.
   assign gstall = 
      is_load[0][2] & ((rs_re[0][1] & rssel[0][1] == rdsel[0][2]) | (rt_re[0][1] & rtsel[0][1] == rdsel[0][2] & ~is_store[0][1]) | is_branch[0][1]) ? 2'b11 : 
      is_load[1][2] & ((rs_re[0][1] & rssel[0][1] == rdsel[1][2]) | (rt_re[0][1] & rtsel[0][1] == rdsel[1][2] & ~is_store[0][1]) | is_branch[0][1]) ? 2'b11 : 
      2'b00;
   // Switch: D.B needs value from D.A (including nzp bits), both insns need memory, or D.B load to use.
   assign gswitch = 
      (rs_re[1][1] & rssel[1][1] == rdsel[0][1] & rd_we[0][1]) | (rt_re[1][1] &rtsel[1][1] == rdsel[0][1] & rd_we[0][1]) | (is_branch[1][1] & nzp_we[0][1]) ? 2'b01 :
      (is_store[0][1] | is_load[0][1]) & (is_store[1][1] | is_load[1][1]) ? 2'b01 :
      is_load[0][2] & ((rs_re[1][1] & rssel[1][1] == rdsel[0][2]) | (rt_re[1][1] & rtsel[1][1] == rdsel[0][2] & ~is_store[1][1]) | is_branch[1][1]) ? 2'b11 : 
      is_load[1][2] & ((rs_re[1][1] & rssel[1][1] == rdsel[1][2]) | (rt_re[1][1] & rtsel[1][1] == rdsel[1][2] & ~is_store[1][1]) | is_branch[1][1]) ? 2'b11 : 
      2'b00;

   /*** EXECUTE ***/

   // What the nzp bits would be here.
   // Even if ahead is NOP it still will have correct NZP values.
   wire [2:0] nzp_ahead [1:0];
   assign nzp_ahead[0] = nzp_we[1][3] ? {n_in[1][3], z_in[1][3], p_in[1][3]} : nzp[1][3];
   // Assuming A doesn't write if I need nzp bits?
   assign nzp_ahead[1] = nzp_ahead[0];

   for (j = 0; j < 2; j=j+1) begin
      // Check if we mispredicted.
      assign gmispred[j] = is_control_insn[j][2] | (is_branch[j][2] & ((insn[j][2][11] & nzp_ahead[j][2]) | (insn[j][2][10] & nzp_ahead[j][1]) | (insn[j][2][9] & nzp_ahead[j][0])));
      // MX and WX bypass into rs.
      assign bypassed_rs_data[j][2] = 
         (rssel[j][2] == rdsel[1][3] & rd_we[1][3]) ? wdata[1][3] : 
         (rssel[j][2] == rdsel[0][3] & rd_we[0][3]) ? wdata[0][3] : 
         (rssel[j][2] == rdsel[1][4] & rd_we[1][4]) ? wdata[1][4] : 
         (rssel[j][2] == rdsel[0][4] & rd_we[0][4]) ? wdata[0][4] : 
         rs_data[j][2];
      // MX and WX bypass into rt.
      assign bypassed_rt_data[j][2] = 
         (rtsel[j][2] == rdsel[1][3] & rd_we[1][3]) ? wdata[1][3] : 
         (rtsel[j][2] == rdsel[0][3] & rd_we[0][3]) ? wdata[0][3] : 
         (rtsel[j][2] == rdsel[1][4] & rd_we[1][4]) ? wdata[1][4] : 
         (rtsel[j][2] == rdsel[0][4] & rd_we[0][4]) ? wdata[0][4] : 
         rt_data[j][2];

      lc4_alu alu (
         .i_insn(insn[j][2]),
         .i_r1data(bypassed_rs_data[j][2]),
         .i_r2data(bypassed_rt_data[j][2]),
         .i_pc(pc[j][2]),
         .o_result(alu_res[j][2])
      );
   end

   /*** MEMORY ***/

   for (j = 0; j < 2; j=j+1) begin
      // Set ppline stuff.
      assign dmem_we[j][3] = is_store[j][3];
      assign dmem_addr[j][3] = (is_load[j][3] | is_store[j][3]) ? alu_res[j][3] : 16'b0;
      assign dmem_out[j][3] = is_store[j][3] ? bypassed_rt_data[j][3] : 16'b0;
      assign dmem_in[j][3] = i_cur_dmem_data;
      assign wdata[j][3] = is_load[j][3] ? dmem_in[j][3] : (select_pc_plus_one[j][3] ? pc_plus_one[j][3] : alu_res[j][3]);

      // No bypass for rs.
      assign bypassed_rs_data[j][3] = rs_data[j][3];

      // New nzp bits.
      assign n_in[j][3] = (wdata[j][3][15] == 1'b1);
      assign z_in[j][3] = (wdata[j][3] == 16'b0);
      assign p_in[j][3] = ~n_in[j][3] & ~z_in[j][3];
   end
   // WM and MM bypass into rt only for store.
   assign bypassed_rt_data[0][3] = 
      rd_we[1][3] & rtsel[0][3] == rdsel[1][3] ? wdata[1][3] : 
      rd_we[0][4] & rtsel[0][3] == rdsel[0][4] ? wdata[0][4] : 
      rd_we[1][4] & rtsel[0][3] == rdsel[1][4] ? wdata[1][4] : 
      rt_data[0][3];
   assign bypassed_rt_data[1][3] = 
      rd_we[0][4] & rtsel[1][3] == rdsel[0][4] ? wdata[0][4] : 
      rd_we[1][4] & rtsel[1][3] == rdsel[1][4] ? wdata[1][4] : 
      rt_data[1][3];

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

   /*** DEBUGGING ***/

   always @(posedge gwe) begin
      if ($time < 16'd5200)
         $display("--------------------------------------------------------------");
      if ($time < 16'd5200)
         $display("gmispred A    %h", gmispred[0]);
      if ($time < 16'd5200)
         $display("gmispred B    %h", gmispred[1]);
      if ($time < 16'd5200)
         $display("gstall        %h", gstall);
      if ($time < 16'd5200)
         $display("gswitch       %h", gswitch);
      if ($time < 16'd5200)
         $display("flush A       %h %h %h %h %h", flush[0][0], flush[0][1], flush[0][2], flush[0][3], flush[0][4]);
      if ($time < 16'd5200)
         $display("flush B       %h %h %h %h %h", flush[1][0], flush[1][1], flush[1][2], flush[1][3], flush[1][4]);
      if ($time < 16'd5200)
         $display("stall A       %h %h %h %h %h", stall[0][0], stall[0][1], stall[0][2], stall[0][3], stall[0][4]);
      if ($time < 16'd5200)
         $display("stall B       %h %h %h %h %h", stall[1][0], stall[1][1], stall[1][2], stall[1][3], stall[1][4]);
      if ($time < 16'd5200)
         $display("switch A      %h %h %h %h %h", switch[0][0], switch[0][1], switch[0][2], switch[0][3], switch[0][4]);
      if ($time < 16'd5200)
         $display("switch B      %h %h %h %h %h", switch[1][0], switch[1][1], switch[1][2], switch[1][3], switch[1][4]);
      if ($time < 16'd5200)
         $display("insn A        %h %h %h %h %h", insn[0][0], insn[0][1], insn[0][2], insn[0][3], insn[0][4]);
      if ($time < 16'd5200)
         $display("insn B        %h %h %h %h %h", insn[1][0], insn[1][1], insn[1][2], insn[1][3], insn[1][4]);
      if ($time < 16'd5200)
         $display("rs_data A     %h %h %h %h %h", rs_data[0][0], rs_data[0][1], rs_data[0][2], rs_data[0][3], rs_data[0][4]);
      if ($time < 16'd5200)
         $display("rs_data B     %h %h %h %h %h", rs_data[1][0], rs_data[1][1], rs_data[1][2], rs_data[1][3], rs_data[1][4]);
      if ($time < 16'd5200)
         $display("rt_data A     %h %h %h %h %h", rt_data[0][0], rt_data[0][1], rt_data[0][2], rt_data[0][3], rt_data[0][4]);
      if ($time < 16'd5200)
         $display("rt_data B     %h %h %h %h %h", rt_data[1][0], rt_data[1][1], rt_data[1][2], rt_data[1][3], rt_data[1][4]);
      if ($time < 16'd5200)
         $display("wdata A       %h %h %h %h %h", wdata[0][0], wdata[0][1], wdata[0][2], wdata[0][3], wdata[0][4]);
      if ($time < 16'd5200)
         $display("wdata B       %h %h %h %h %h", wdata[1][0], wdata[1][1], wdata[1][2], wdata[1][3], wdata[1][4]);
      if ($time < 16'd5200)
         $display("rssel A       %h    %h    %h    %h    %h", rssel[0][0], rssel[0][1], rssel[0][2], rssel[0][3], rssel[0][4]);
      if ($time < 16'd5200)
         $display("rssel B       %h    %h    %h    %h    %h", rssel[1][0], rssel[1][1], rssel[1][2], rssel[1][3], rssel[1][4]);
      if ($time < 16'd5200)
         $display("rtsel A       %h    %h    %h    %h    %h", rtsel[0][0], rtsel[0][1], rtsel[0][2], rtsel[0][3], rtsel[0][4]);
      if ($time < 16'd5200)
         $display("rtsel B       %h    %h    %h    %h    %h", rtsel[1][0], rtsel[1][1], rtsel[1][2], rtsel[1][3], rtsel[1][4]);
      if ($time < 16'd5200)
         $display("rdsel A       %h    %h    %h    %h    %h", rdsel[0][0], rdsel[0][1], rdsel[0][2], rdsel[0][3], rdsel[0][4]);
      if ($time < 16'd5200)
         $display("rdsel B       %h    %h    %h    %h    %h", rdsel[1][0], rdsel[1][1], rdsel[1][2], rdsel[1][3], rdsel[1][4]);
      if ($time < 16'd5200)
         $display("stall_type A  %h    %h    %h    %h    %h", stall_type[0][0], stall_type[0][1], stall_type[0][2], stall_type[0][3], stall_type[0][4]);
      if ($time < 16'd5200)
         $display("stall_type B  %h    %h    %h    %h    %h", stall_type[1][0], stall_type[1][1], stall_type[1][2], stall_type[1][3], stall_type[1][4]);
      if ($time < 16'd5200)
         $display("dmem_addr A   %h %h %h %h %h", dmem_addr[0][0], dmem_addr[0][1], dmem_addr[0][2], dmem_addr[0][3], dmem_addr[0][4]);
      if ($time < 16'd5200)
         $display("dmem_addr B   %h %h %h %h %h", dmem_addr[1][0], dmem_addr[1][1], dmem_addr[1][2], dmem_addr[1][3], dmem_addr[1][4]);
      if ($time < 16'd5200)
         $display("dmem_in A     %h %h %h %h %h", dmem_in[0][0], dmem_in[0][1], dmem_in[0][2], dmem_in[0][3], dmem_in[0][4]);
      if ($time < 16'd5200)
         $display("dmem_in B     %h %h %h %h %h", dmem_in[1][0], dmem_in[1][1], dmem_in[1][2], dmem_in[1][3], dmem_in[1][4]);
      if ($time < 16'd5200)
         $display("dmem_out A    %h %h %h %h %h", dmem_out[0][0], dmem_out[0][1], dmem_out[0][2], dmem_out[0][3], dmem_out[0][4]);
      if ($time < 16'd5200)
         $display("dmem_out B    %h %h %h %h %h", dmem_out[1][0], dmem_out[1][1], dmem_out[1][2], dmem_out[1][3], dmem_out[1][4]);
      if ($time < 16'd5200)
         $display("alu_res A     %h %h %h %h %h", alu_res[0][0], alu_res[0][1], alu_res[0][2], alu_res[0][3], alu_res[0][4]);
      if ($time < 16'd5200)
         $display("alu_res B     %h %h %h %h %h", alu_res[1][0], alu_res[1][1], alu_res[1][2], alu_res[1][3], alu_res[1][4]);
   end

endmodule
