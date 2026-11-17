// tb_nexys4_top.v - board-level smoke test of nexys4_top with the demo program
// Build the demo with a small CORE_HZ so things move quickly in simulation:
//   make -C sw/demo clean all CFLAGS_EXTRA=-DCORE_HZ=4000
// then run sim/run_board_sim.sh
`timescale 1ns/1ps

module tb_nexys4_top;
    reg        clk = 1'b0;
    reg        rstn = 1'b0;
    reg [15:0] sw = 16'hBEEF;
    reg        btnc = 0, btnu = 0, btnl = 0, btnr = 0, btnd = 0;
    always #5 clk = ~clk;

    wire [15:0] led;
    wire [6:0]  seg;
    wire        dp;
    wire [7:0]  an;

    nexys4_top dut (
        .CLK100MHZ(clk), .CPU_RESETN(rstn), .SW(sw),
        .BTNC(btnc), .BTNU(btnu), .BTNL(btnl), .BTNR(btnr), .BTND(btnd),
        .LED(led), .SEG(seg), .DP(dp), .AN(an)
    );

    wire [31:0] disp = dut.sevenseg;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_nexys4_top.vcd");
            $dumpvars(0, tb_nexys4_top);
        end
        #100 rstn = 1'b1;

        #200000;
        $display("t=%0t  LED=%016b  7seg=%08h", $time, led, disp);
        #200000;
        $display("t=%0t  LED=%016b  7seg=%08h", $time, led, disp);
        if (disp[31:16] !== 16'hBEEF) $display("ERROR: switches not shown on display");

        btnd = 1; #200000;
        $display("t=%0t  BTND held, CPI x100 = %04h", $time, disp[15:0]);
        btnd = 0;

        btnc = 1; #2000; btnc = 0; #50000;
        $display("t=%0t  after BTNC  7seg=%08h", $time, disp);
        $display("instret=%0d cycles=%0d", dut.u_soc.instret, dut.u_soc.cycles);
        $finish;
    end
endmodule
