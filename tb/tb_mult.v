`timescale 1ns/1ps

// Exhaustive self-checking testbench for mult_array (latency 2 cycles).
// Inputs change on the falling edge, one new vector every cycle, so the
// pipeline is full and p must equal the product of the inputs applied two
// rising edges earlier. This checks the latency and the throughput, not only
// the multiplication. Reset checks: p is 0 while rst_n is low (also with a
// clock running and nonzero inputs), reset clears p without a clock edge
// (asynchronous), and after release the first result is 0 (a_r, b_r were
// cleared) and the second one is the new product (recovery).
module tb_mult;

    reg        clk;
    reg        rst_n;
    reg  [3:0] a, b;
    wire [7:0] p;

    integer n;
    integer errors;
    integer count;

    mult_array dut (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .p(p));

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ea, eb: the operands whose product p should hold now
    task check(input [3:0] ea, input [3:0] eb, input [7:0] expected, input [8*24-1:0] what);
        begin
            if (p !== expected) begin
                errors = errors + 1;
                $display("MISMATCH (%0s): a=%0d b=%0d expected=%0d got=%0d (t=%0t)",
                         what, ea, eb, expected, p, $time);
            end
        end
    endtask

    initial begin
        $dumpfile("mult.vcd");
        $dumpvars(0, tb_mult);

        errors = 0;
        count  = 0;

        // Reset for the first 2 clock cycles, with nonzero inputs applied so a
        // missing or synchronous reset is visible: p must stay 0.
        rst_n = 1'b0;
        a     = 4'd15;
        b     = 4'd15;
        repeat (2) begin
            @(negedge clk);
            check(a, b, 8'd0, "during reset");
        end

        // Release reset and stream all 256 vectors, one per clock cycle.
        // Vector n is applied at falling edge n and captured at rising edge n+1;
        // its product is in p after rising edge n+2, checked at falling edge n+2.
        rst_n = 1'b1;
        for (n = 0; n <= 256; n = n + 1) begin
            if (n < 256) begin
                a = n / 16;
                b = n % 16;
            end
            @(negedge clk);
            if (n == 0)
                check(a, b, 8'd0, "first cycle after reset");
            else begin
                count = count + 1;
                check((n - 1) / 16, (n - 1) % 16, ((n - 1) / 16) * ((n - 1) % 16), "vector");
            end
        end

        // Asynchronous reset in the middle of operation.
        a = 4'd15;
        b = 4'd15;
        repeat (2) @(negedge clk);
        check(4'd15, 4'd15, 8'd225, "before mid-run reset");
        @(posedge clk);
        #1 rst_n = 1'b0;              // between clock edges
        #7 check(a, b, 8'd0, "async reset, no clock");
        @(negedge clk);
        a = 4'd3;
        b = 4'd5;
        @(negedge clk);
        check(a, b, 8'd0, "held in reset");
        rst_n = 1'b1;
        @(negedge clk);
        check(4'd0, 4'd0, 8'd0, "recovery, cycle 1");
        @(negedge clk);
        check(4'd3, 4'd5, 8'd15, "recovery, cycle 2");

        if (errors == 0)
            $display("PASS: %0d vectors checked, %0d errors", count, errors);
        else
            $display("FAIL: %0d vectors checked, %0d errors", count, errors);
        $finish;
    end

endmodule
