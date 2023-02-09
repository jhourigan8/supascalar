/* TODO: INSERT NAME AND PENNKEY HERE */

`timescale 1ns / 1ps
`default_nettype none

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
   assign g = a & b;
   assign p = a | b;
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals 
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits collectively generate a carry (ignoring cin)
 * @param pout whether these 4 bits collectively would propagate an incoming carry (ignoring cin)
 * @param cout the carry outs for the low-order 3 bits
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout);

  assign cout[0] = (pin[0] & cin) | gin[0];
  assign cout[1] = (pin[1] & pin[0] & cin) | (pin[1] & gin[0]) | gin[1];
  assign cout[2] = (pin[2] & pin[1] & pin[0] & cin) | (pin[2] & pin[1] & gin[0]) | (pin[2] & gin[1]) | gin[2];
  assign gout = (pin[3] & pin[2] & pin[1] & gin[0]) | (pin[3] & pin[2] & gin[1]) | (pin[3] & gin[2]) | gin[3];
  assign pout = pin[0] & pin[1] & pin[2] & pin[3];
   
endmodule

/**
 * 16-bit Carry-Lookahead Adder
 * @param a first input
 * @param b second input
 * @param cin carry in
 * @param sum sum of a + b + carry-in
 */
module cla16
  (input wire [15:0]  a, b,
   input wire         cin,
   output wire [15:0] sum);

  output wire [15:1] cout;
  output wire [15:0] gin;
  output wire [15:0] pin;
  output wire [4:0] gout;
  output wire [4:0] pout;

  wire [3:0] cout2

  integer i = 0;
  for (i = 0; i < 16; i = i+1) begin
    assign gin[i] = a[i] & b[i];
    assign pin[i] = a[i] ^ b[i];
  end

  for (i = 0; i < 4; i = i+1) begin
    gp4(gin[4 * i + 3 : 4 * i], pin[4 * i + 3 : 4 * i], 
        cin, gout[i], pout[i], 
        cout[4 * i + 3 : 4 * i + 1]);
  end

  gp4(gout[3:0], pout[3:0], cin, gout[4], pout[4], cout2[2:0]);

  for (i = 0; i < 3; i = i+1) begin
    assign cout[4 * i + 4] = cout[i];
  end

  for (i = 1; i < 4; i = i+1) begin
    gp4(gin[4 * i + 3 : 4 * i], pin[4 * i + 3 : 4 * i], 
        cout2[i - 1], gout[i], pout[i], 
        cout[4 * i + 3 : 4 * i + 1]);
  end

  for (i = 0; i < 16; i = i+1) begin
    assign sum[i] = a[i] ^ b[i] ^ cout[i];
  end

endmodule


/** Lab 2 Extra Credit, see details at
  https://github.com/upenn-acg/cis501/blob/master/lab2-alu/lab2-cla.md#extra-credit
 If you are not doing the extra credit, you should leave this module empty.
 */
module gpn
  #(parameter N = 4)
  (input wire [N-1:0] gin, pin,
   input wire  cin,
   output wire gout, pout,
   output wire [N-2:0] cout);
 
endmodule
