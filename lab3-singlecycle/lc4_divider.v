/* Jack Hourigan (hojack) */

`timescale 1ns / 1ps
`default_nettype none

module lc4_divider(input  wire [15:0] i_dividend,
                   input  wire [15:0] i_divisor,
                   output wire [15:0] o_remainder,
                   output wire [15:0] o_quotient);

      wire[15:0] dividends [16:0];
      wire[15:0] quotients [16:0];
      wire[15:0] remainders [16:0];

      assign dividends[0] = i_dividend;
      assign quotients[0] = 16'b0;
      assign remainders[0] = 16'b0;

      genvar i;
      for (i = 0; i < 16; i = i+1) begin
            lc4_divider_one_iter iter(
                  .i_dividend(dividends[i]),
                  .i_divisor(i_divisor),
                  .i_remainder(remainders[i]),
                  .i_quotient(quotients[i]),
                  .o_dividend(dividends[i+1]),
                  .o_remainder(remainders[i+1]),
                  .o_quotient(quotients[i+1])
            );
      end

      assign o_remainder = i_divisor ? remainders[16] : 0;
      assign o_quotient = i_divisor ? quotients[16] : 0;


endmodule // lc4_divider

module lc4_divider_one_iter(input  wire [15:0] i_dividend,
                            input  wire [15:0] i_divisor,
                            input  wire [15:0] i_remainder,
                            input  wire [15:0] i_quotient,
                            output wire [15:0] o_dividend,
                            output wire [15:0] o_remainder,
                            output wire [15:0] o_quotient);

      wire [15:0] tmp_remainder;
      wire sub;

      assign tmp_remainder = {i_remainder[14:0], i_dividend[15]};
      assign sub = tmp_remainder >= i_divisor;
      assign o_quotient = {i_quotient[14:0], sub};
      assign o_remainder = sub ? tmp_remainder - i_divisor : tmp_remainder;
      assign o_dividend = i_dividend <<< 1;


endmodule
