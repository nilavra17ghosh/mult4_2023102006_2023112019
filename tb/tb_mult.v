`timescale 1ns/1ps

// Exhaustive self-checking testbench for mult_array (latency 2 cycles).
// Inputs change on the falling edge; edge 1 registers a/b, edge 2 registers p,
// and p is checked on the following falling edge.
module tb_mult;

    reg        clk;
    reg        rst_n;
    reg  [3:0] a, b;
    wire [7:0] p;

    integer i, j;
    integer errors;
    integer count;

    mult_array dut (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .p(p));

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("mult.vcd");
        $dumpvars(0, tb_mult);

        rst_n  = 1'b0;
        a      = 4'd0;
        b      = 4'd0;
        errors = 0;
        count  = 0;

        // hold reset low for the first 2 clock cycles
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i;
                b = j;
                @(posedge clk);     // edge 1: inputs registered
                @(posedge clk);     // edge 2: product registered
                @(negedge clk);     // check after outputs settle
                count = count + 1;
                if (p !== i * j) begin
                    errors = errors + 1;
                    $display("MISMATCH: a=%0d b=%0d expected=%0d got=%0d (t=%0t)",
                             i, j, i * j, p, $time);
                end
            end
        end

        if (errors == 0)
            $display("PASS: %0d vectors checked, %0d errors", count, errors);
        else
            $display("FAIL: %0d vectors checked, %0d errors", count, errors);
        $finish;
    end

endmodule
