/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

`timescale 1ns / 1ps
`default_nettype none

module lc4_alu(input  wire [15:0] i_insn,
               input wire [15:0]  i_pc,
               input wire [15:0]  i_r1data,
               input wire [15:0]  i_r2data,
               output wire [15:0] o_result);
      
      // top level mux
      // even though some of these cases are trivial (e.g. all zeroes)
      // for uniformity just going to mux them anyway
      assign o_result = 
            (i_insn[15:12] == 4'b0000) ? branch_out :
            (i_insn[15:12] == 4'b0001) ? arith_out :
            (i_insn[15:12] == 4'b0010) ? cmp_out :
            (i_insn[15:12] == 4'b0100) ? jsr_out :
            (i_insn[15:12] == 4'b0101) ? logic_out :
            (i_insn[15:12] == 4'b0110) ? load_out :
            (i_insn[15:12] == 4'b0111) ? store_out :
            (i_insn[15:12] == 4'b1000) ? rti_out :
            (i_insn[15:12] == 4'b1001) ? const_out :
            (i_insn[15:12] == 4'b1010) ? shift_out :
            (i_insn[15:12] == 4'b1100) ? jump_out :
            (i_insn[15:12] == 4'b1101) ? hiconst_out :
            // (i_insn[15:12] == 4’b1111)
            trap_out;

      // divider
      wire [15:0] divider_o_remainder;
      wire [15:0] divider_o_quotient;

      // only used for DIV and MOD
      // both want Rt and Rs inputs so no need to mux
      lc4_divider divider(
            i_r1data,
            i_r2data,
            divider_o_remainder,
            divider_o_quotient
      );

      // adder
      wire [15:0] adder_a;
      wire [15:0] adder_b;
      wire adder_cin;
      wire [15:0] adder_sum;
      wire [32:0] adder_tmp;
  
      assign adder_tmp = 
            // branch
            (i_insn[15:12] == 4'b0000) ? {i_pc, i_insn[8] ? {7'h7F, i_insn[8:0]} : {7'b0, i_insn[8:0]}, 1'b1} :
            // arith
            (i_insn[15:12] == 4'b0001) ? 
                  // add
                  ((i_insn[5:3] == 3'b000) ? {i_r1data, i_r2data, 1'b0} :
                  // sub
                  (i_insn[5:3] == 3'b010) ? {i_r1data, ~i_r2data, 1'b1} :
                  // add immediate
                  {i_r1data, i_insn[4] ? {11'h7FF, i_insn[4:0]} : {11'b0, i_insn[4:0]}, 1'b0}) :
            // load
            (i_insn[15:12] == 4'b0110) ? {i_r1data, i_insn[5] ? {10'h3FF, i_insn[5:0]} : {10'b0, i_insn[5:0]}, 1'b0} :
            // store
            (i_insn[15:12] == 4'b0111) ? {i_r1data, i_insn[5] ? {10'h3FF, i_insn[5:0]} : {10'b0, i_insn[5:0]}, 1'b0} :
            // (i_insn[15:12] == 4'b1100)
            // jump
            {i_pc, i_insn[10] ? {5'h1F, i_insn[10:0]} : {5'b0, i_insn[10:0]}, 1'b1};

      assign adder_a = adder_tmp[32:17];
      assign adder_b = adder_tmp[16:1];
      assign adder_cin = adder_tmp[0];

      cla16 adder(
            adder_a,
            adder_b,
            adder_cin,
            adder_sum
      );

      // 0000 -- branch
      wire [15:0] branch_out;
      assign branch_out = adder_sum;

      // 0001 -- arith
      wire [15:0] arith_out;
      assign arith_out = 
            // add
            (i_insn[5:3] == 3'b000) ? adder_sum :
            // mult
            (i_insn[5:3] == 3'b001) ? i_r1data * i_r2data:
            // sub
            (i_insn[5:3] == 3'b010) ? adder_sum :
            // div
            (i_insn[5:3] == 3'b011) ? divider_o_quotient:
            // default 
            // add imm
            adder_sum;

      // 0010 -- cmp
      wire [15:0] cmp_out;
      assign cmp_out = 
            // cmp
            (i_insn[8:7] == 2'b00) ? 
                  (($signed(i_r1data) > $signed(i_r2data)) ? 
                  16'b1 : (i_r1data == i_r2data) ? 
                  16'b0 : 16'hFFFF) :
            // cmpu
            (i_insn[8:7] == 2'b01) ? 
                  ((i_r1data > i_r2data) ? 
                  16'b1 : (i_r1data == i_r2data) ? 
                  16'b0 : 16'hFFFF) :
            // cmpi
            (i_insn[8:7] == 2'b10) ? 
                  (($signed(i_r1data) > $signed(i_insn[6] ? {9'h1FF, i_insn[6:0]} : {9'b0, i_insn[6:0]})) ? 
                  16'b1 : (i_r1data == (i_insn[6] ? {9'h1FF, i_insn[6:0]} : {9'b0, i_insn[6:0]})) ? 
                  16'b0 : 16'hFFFF) :
            // (i_insn[8:7] == 2'b11)
            // cmpiu
                  ((i_r1data > {9'b0, i_insn[6:0]}) ? 
                  16'b1 : (i_r1data == {9'b0, i_insn[6:0]}) ? 
                  16'b0 : 16'hFFFF);

      // 0100 -- jsr
      wire [15:0] jsr_out;
      assign jsr_out = 
            // jsrr
            (i_insn[11] == 1'b0) ? i_r1data :
            // i_insn[11] == 1'b1
            // jsr
            (i_pc & 16'h8000) | (i_insn[10:0] << 4); 

      // 0101 -- logic
      wire [15:0] logic_out;
      assign logic_out = 
            // and
            (i_insn[5:3] == 3'b000) ? i_r1data & i_r2data :
            // not
            (i_insn[5:3] == 3'b001) ? ~i_r1data :
            // or
            (i_insn[5:3] == 3'b010) ? i_r1data | i_r2data :
            // xor
            (i_insn[5:3] == 3'b011) ? i_r1data ^ i_r2data :
            // default
            // and immed
            i_r1data & (i_insn[4] ? {11'h7FF, i_insn[4:0]} : {11'b0, i_insn[4:0]}); 

      // 0110 -- load
      wire [15:0] load_out;
      assign load_out = adder_sum;

      // 0111 -- store
      wire [15:0] store_out;
      assign store_out = adder_sum;

      // 1000 -- rti
      wire [15:0] rti_out;
      assign rti_out = i_r1data;

      // 1001 -- const
      wire [15:0] const_out;
      assign const_out = i_insn[8] ? {7'h7F, i_insn[8:0]} : {7'b0, i_insn[8:0]};

      // 1010 -- shift
      wire [15:0] shift_out;
      assign shift_out = 
            // sll
            (i_insn[5:4] == 2'b00) ? $signed(i_r1data) << i_insn[3:0] :
            // sra
            (i_insn[5:4] == 2'b01) ? $signed(i_r1data) >>> i_insn[3:0] :
            // srl
            (i_insn[5:4] == 2'b10) ? $signed(i_r1data) >> i_insn[3:0] :
            // i_insn[5:4] == 2'b11
            // mod
            $signed(divider_o_remainder);

      // 1100 -- jump
      wire [15:0] jump_out;
      assign jump_out = 
            // jmpr
            (i_insn[11] == 1'b0) ? i_r1data : 
            // i_insn[10] == 1'b1
            // jmp
            adder_sum; 

      // 1101 -- hiconst
      wire [15:0] hiconst_out;
      assign hiconst_out = (i_r1data & 16'h00FF) | ({8'b0, i_insn[7:0]} << 8);

      // 1111 -- trap
      wire [15:0] trap_out;
      assign trap_out = 16'h8000 | {8'b0, i_insn[7:0]};

endmodule
