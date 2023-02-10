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

      // mux to set operands
      always_comb case (i_insn[15:12]) 
            4'b0000:
                  begin
                        // PC + 1 + IMM9
                        assign adder_a = i_pc;
                        assign adder_b = {7'b0, i_insn[8:0]};
                        assign adder_cin = 1;
                  end
            4'b0001:
                  begin
                        always_comb case (i_insn[5:3]) 
                              3'b000: 
                                    begin
                                          // Rd + Rt
                                          assign adder_a = i_r1data;
                                          assign adder_b = i_r2data;
                                          assign adder_cin = 0;
                                    end
                              3'b010: 
                                    begin
                                          // Rd - Rt
                                          assign adder_a = i_r1data;
                                          assign adder_b = ~i_r2data;
                                          assign adder_cin = 1;
                                    end
                              default: 
                                    begin
                                          // Rd + IMM5
                                          assign adder_a = i_r1data;
                                          assign adder_b = {11'b0, i_insn[4:0]};
                                          assign adder_cin = 0;
                                    end
                        endcase end
                  end
            // not needed for 0010
            // no 0011
            // not needed for 0100
            // not needed for 0101
            4'b0110:
                  begin
                        assign adder_a = i_r1data;
                        assign adder_b = {10'b0, i_insn[5:0]};
                        assign adder_cin = 0;
                  end
            4'b0111:
                  begin
                        assign adder_a = i_r1data;
                        assign adder_b = {10'b0, i_insn[5:0]};
                        assign adder_cin = 0;
                  end
            // not needed for b1000
            // not needed for b1001
            // not needed for 1010
            // no 1011
            4'b1100:
                  begin
                        // PC + 1 + IMM11
                        assign adder_a = i_pc;
                        assign adder_b = {5'b0, i_insn[10:0]};
                        assign adder_cin = 1;
                  end
            // not needed for 1101
            // no 1110
            // note needed for 1111
      endcase end

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
      always_comb case (i_insn[5:3]) 
            3'b000: 
                  begin
                        assign arith_out = adder_sum;
                  end
            3'b001: 
                  begin
                        assign airth_out = i_r1data * i_r2data;
                  end
            3'b010: 
                  begin
                        assign arith_out = adder_sum;
                  end
            3'b011: 
                  begin
                        assign arith_out = divider_o_quotient;
                  end
            default: 
                  begin
                        assign arith_out = adder_sum;
                  end
      endcase end

      // 0010 -- cmp
      wire [15:0] cmp_out;
      always_comb case (i_insn[8:7]) 
            2'b00: 
                  begin
                        assign cmp_out = ($signed(i_r1data) > $signed(i_r2data)) ? 
                              16'b1 : (i_r1data == i_r2data) ? 16'b0 : 16'hFFFF;
                  end
            2'b01: 
                  begin
                        assign cmp_out = (i_r1data > i_r2data) ? 
                              16'b1 : (i_r1data == i_r2data) ? 16'b0 : 16'hFFFF;
                  end
            2'b10: 
                  begin
                        assign cmp_out = ($signed(i_r1data) > $signed({9'b0, i_insn[6:0]})) ? 
                              16'b1 : (i_r1data == {9'b0, i_insn[6:0]}) ? 16'b0 : 16'hFFFF;
                  end
            2'b11: 
                  begin
                        assign cmp_out = (i_r1data > {9'b0, i_insn[6:0]}) ? 
                              16'b1 : (i_r1data == {9'b0, i_insn[6:0]}) ? 16'b0 : 16'hFFFF;
                  end
      endcase end

      // 0100 -- jsr
      wire [15:0] jsr_out;
      always_comb case (i_insn[10]) 
            1'b0:
                  begin
                        assign jsr_out = i_r1data;
                  end
            1'b1:
                  begin
                        assign jsr_out = (i_pc & 16'h8000) | ({5'b0, i_insn[10:0]} << 4);
                  end
      endcase end

      // 0101 -- logic
      wire [15:0] logic_out;
      always_comb case (i_insn[5:3]) 
            3'b000: 
                  begin
                        assign logic_out = i_r1data & i_r2data;
                  end
            3'b001: 
                  begin
                        assign logic_out = ~i_r1data;
                  end
            3'b010: 
                  begin
                        assign logic_out = i_r1data | i_r2data;
                  end
            3'b011: 
                  begin
                        assign logic_out = i_r1data ^ i_r2data;
                  end
            default: 
                  begin
                        assign logic_out = i_r1data ^ {11'b0, i_insn[4:0]};
                  end
      endcase end

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
      always_comb case (i_insn[5:4]) 
            2'b00: 
                  begin
                        assign shift_out = i_r1data << i_insn[3:0];
                  end
            2'b01: 
                  begin
                        assign shift_out = i_r1data >>> i_insn[3:0];
                  end
            2'b10: 
                  begin
                        assign shift_out = i_r1data >> i_insn[3:0];
                  end
            2'b11:
                  begin
                        assign shift_out = divider_o_remainder;
                  end
      endcase end

      // 1100 -- jump
      wire [15:0] jump_out;
      always_comb case(i_insn[10]) 
            1'b0:
                  begin
                        assign jump_out = i_r1data;
                  end
            1'b1:
                  begin
                        assign jump_out = adder_sum;
                  end
      endcase end

      // 1101 -- hiconst
      wire [15:0] hiconst_out;
      assign hiconst_out = (i_r1data & 16'h00FF) | ({8'b0, i_insn[7:0]} << 8);

      // 1111 -- trap
      wire [15:0] trap_out;
      assign trap_out = 16'h8000 | {8'b0, i_insn[7:0]};

endmodule
