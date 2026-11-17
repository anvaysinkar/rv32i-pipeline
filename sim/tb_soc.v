// tb_soc.v - self-checking testbench for rv32_soc
// Loads imem.hex / dmem.hex from the current directory, runs until the program
// writes TOHOST, then prints PASS/FAIL with cycle and instruction counts.
// Add +vcd to dump waveforms to tb_soc.vcd.
`timescale 1ns/1ps

module tb_soc;
    parameter IMEM_INIT = "imem.hex";
    parameter DMEM_INIT = "dmem.hex";
    parameter TIMEOUT   = 200000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;   // 100 MHz, same as Nexys4

    wire [15:0] led;
    wire [31:0] sevenseg, tohost;
    wire        tohost_we;

    rv32_soc #(.IMEM_INIT(IMEM_INIT), .DMEM_INIT(DMEM_INIT)) dut (
        .clk(clk), .rst_n(rst_n), .sw(16'h00A5), .btn(5'b0),
        .led(led), .sevenseg(sevenseg), .tohost(tohost), .tohost_we(tohost_we)
    );

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_soc.vcd");
            $dumpvars(0, tb_soc);
        end
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
    end

    always @(posedge clk) begin
        if (tohost_we) begin
            if (tohost == 32'd1)
                $display("PASS  cycles=%0d instret=%0d CPI=%0.3f",
                         dut.cycles, dut.instret,
                         dut.instret ? (1.0 * dut.cycles) / dut.instret : 0.0);
            else
                $display("FAIL  test #%0d (tohost=0x%08h)", tohost >> 1, tohost);
            $finish;
        end
        if (cyc > TIMEOUT) begin
            $display("TIMEOUT after %0d cycles, pc=0x%08h", cyc, dut.u_core.pc_q);
            $finish;
        end
    end
endmodule
