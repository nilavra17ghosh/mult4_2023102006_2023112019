`timescale 1ns/1ps

// 4x4 unsigned array multiplier, registered inputs and output (latency 2).
module mult_array (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg  [7:0] p
);

    reg [3:0] a_r, b_r;

    // partial products: ppi[j] = a[j] & b[i]
    wire [3:0] pp0 = a_r & {4{b_r[0]}};
    wire [3:0] pp1 = a_r & {4{b_r[1]}};
    wire [3:0] pp2 = a_r & {4{b_r[2]}};
    wire [3:0] pp3 = a_r & {4{b_r[3]}};

    wire [3:0] s1, s2, s3;
    wire [4:0] c1, c2, c3;

    assign c1[0] = 1'b0;
    assign c2[0] = 1'b0;
    assign c3[0] = 1'b0;

    // bits passed down from each row
    wire [3:0] r0 = {1'b0,  pp0[3], pp0[2], pp0[1]};
    wire [3:0] r1 = {c1[4], s1[3],  s1[2],  s1[1]};
    wire [3:0] r2 = {c2[4], s2[3],  s2[2],  s2[1]};

    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : row
            full_adder fa1 (.a(pp1[j]), .b(r0[j]), .cin(c1[j]), .sum(s1[j]), .cout(c1[j+1]));
            full_adder fa2 (.a(pp2[j]), .b(r1[j]), .cin(c2[j]), .sum(s2[j]), .cout(c2[j+1]));
            full_adder fa3 (.a(pp3[j]), .b(r2[j]), .cin(c3[j]), .sum(s3[j]), .cout(c3[j+1]));
        end
    endgenerate

    wire [7:0] prod = {c3[4], s3[3], s3[2], s3[1], s3[0], s2[0], s1[0], pp0[0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r <= 4'd0;
            b_r <= 4'd0;
            p   <= 8'd0;
        end else begin
            a_r <= a;
            b_r <= b;
            p   <= prod;
        end
    end

endmodule
