/* Mike Zhou (mikezhou) and Jack Hourigan (hojack) */

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

  wire [15:0] gin;
  wire [15:0] pin;
  wire [15:0] cout;
  wire [3:0] gout;
  wire [3:0] pout;
  // not used
  wire gtop;
  wire ptop;
  
  assign cout[0] = cin;

  genvar i;
  for (i = 0; i < 16; i = i+1) begin
    assign gin[i] = a[i] & b[i];
    // i think this can be xor too and it doesn't matter
    assign pin[i] = a[i] | b[i];
  end

  // (1) compute windowed g/p
  // (3) use carry at 4*i to get carries at 4*i + 1, 4*i + 2, 4*i + 3
  for (i = 0; i < 4; i = i+1) begin
    gp4 layer_1_gp (
        gin[4 * i + 3 : 4 * i], 
        pin[4 * i + 3 : 4 * i], 
        cout[4 * i], 
        gout[i], 
        pout[i], 
        cout[4 * i + 3 : 4 * i + 1]
    );
  end

  // (2) use windowed g/p to get the carries at 4, 8, 12
  gp4 layer_2_gp (
    gout[3:0], 
    pout[3:0], 
    cout[0], 
    gtop, 
    ptop, 
    {cout[12], cout[8], cout[4]}
  );

  // (4) now we have all the carries! xor.
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

    // (TOP, BOTTOM) in and chain + generate at from
    wire [N-1:0] pchain [N-1:0];
    wire [N:0] gens;
    assign gens = {gin, cin};
    genvar i;
    for (i = 0; i < N; i = i+1) begin
      assign pchain[i][i] = pin[i] & gens[i];
      genvar j;
      for (j = i+1; j < N; j=j+1) begin
        assign pchain[j][i] = pchain[j-1][i] & pin[j];
      end
    end
    // pchain[j][i] = pin[j] & ... & pin[i] & gens[i]

    for (i = 0; i < N-1; i=i+1) begin
      // get all with top i
      assign cout[i] = | pchain[i][i:0] | gin[i];
    end
    // get all except cin propagate with top N-1
    assign gout = | pchain[N-1][N-1:1] | gin[N-1];
    assign pout = & pin;
 
endmodule
