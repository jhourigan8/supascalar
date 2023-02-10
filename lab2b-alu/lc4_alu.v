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
      always_comb begin case (i_insn[15:12]) 
            4'b0000:
                  assign o_result = branch_out;
            4'b0001:
                  assign o_result = arith_out;
            4'b0010:
                  assign o_result = cmp_out;
            // no 0011
            4'b0100:
                  assign o_result = jsr_out;
            4'b0101:
                  assign o_result = logic_out;
            4'b0110:
                  assign o_result = load_out;
            4'b0111:
                  assign o_result = store_out;
            4'b1000:
                  assign o_result = rti_out;
            4'b1001:
                  assign o_result = const_out;
            4'b1010:
                  assign o_result = shift_out;
            // no 1011
            4'b1100:
                  assign o_result = jump_out;
            4'b1101:
                  assign o_result = hiconst_out;
            // no 1110
            4'b1111:
                  assign o_result = trap_out;
      endcase end

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
            (i_insn[5:3] == 3'b000) ? adder_sum :
            (i_insn[5:3] == 3'b001) ? i_r1data * i_r2data:
            (i_insn[5:3] == 3'b010) ? adder_sum :
            (i_insn[5:3] == 3'b011) ? divider_o_quotient :
            // default
            adder_sum;

      // 0010 -- cmp
      wire [15:0] cmp_out;
      assign cmp_out = 
            (i_insn[8:7] == 2'b00) ? 
                  (($signed(i_r1data) > $signed(i_r2data)) ? 
                  16'b1 : (i_r1data == i_r2data) ? 
                  16'b0 : 16'hFFFF) :
            (i_insn[8:7] == 2'b01) ? 
                  ((i_r1data > i_r2data) ? 
                  16'b1 : (i_r1data == i_r2data) ? 
                  16'b0 : 16'hFFFF) :
            (i_insn[8:7] == 2'b10) ? 
                  (($signed(i_r1data) > $signed({9'b0, i_insn[6:0]})) ? 
                  16'b1 : (i_r1data == {9'b0, i_insn[6:0]}) ? 
                  16'b0 : 16'hFFFF) :
            // (i_insn[8:7] == 2'b11)
                  ((i_r1data > {9'b0, i_insn[6:0]}) ? 
                  16'b1 : (i_r1data == {9'b0, i_insn[6:0]}) ? 
                  16'b0 : 16'hFFFF);

      // 0100 -- jsr
      wire [15:0] jsr_out;
      assign jsr_out = 
            (i_insn[10] == 1'b0) ? i_r1data :
            // i_insn[10] == 1'b1
            (i_pc & 16'h8000) | ({5'b0, i_insn[10:0]} << 4); 

      // 0101 -- logic
      wire [15:0] logic_out;
      assign logic_out = 
            (i_insn[5:3] == 3'b000) ? i_r1data & i_r2data :
            (i_insn[5:3] == 3'b001) ? ~i_r1data :
            (i_insn[5:3] == 3'b010) ? i_r1data | i_r2data :
            (i_insn[5:3] == 3'b011) ? i_r1data ^ i_r2data :
            // default
            i_r1data ^ {11'b0, i_insn[4:0]}; 

      // 0110 -- load
      wire [15:0] load_out;
      assign load_out = adder_sum;

      // 0111 -- store
      wire [15:0] store_out;
      assign load_out = adder_sum;

      // 1000 -- rti
      wire [15:0] rti_out;
      assign rti_out = i_r1data;

      // 1001 -- const
      wire [15:0] const_out;
      assign const_out = {9'b0, i_insn[6:0]};

      // 1010 -- shift
      wire [15:0] shift_out;
      assign shift_out = 
            (i_insn[5:4] == 2'b00) ? i_r1data << i_insn[3:0] :
            (i_insn[5:4] == 2'b01) ? i_r1data >>> i_insn[3:0] :
            (i_insn[5:4] == 2'b10) ? i_r1data >> i_insn[3:0] :
            divider_o_remainder; // i_insn[5:4] == 2'b11

      // 1100 -- jump
      wire [15:0] jump_out;
      assign jump_out = 
            (i_insn[10] == 1'b0) ? i_r1data : 
            adder_sum; // i_insn[10] == 1'b1

      // 1101 -- hiconst
      wire [15:0] hiconst_out;
      assign hiconst_out = (i_r1data & 16'h00FF) | ({8'b0, i_insn[7:0]} << 8);

      // 1111 -- trap
      wire [15:0] trap_out;
      assign trap_out = 16'h8000 | {8'b0, i_insn[7:0]};

endmodule
