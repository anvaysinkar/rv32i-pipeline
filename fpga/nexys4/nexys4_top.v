// nexys4_top.v - Digilent Nexys4 / Nexys4 DDR (Artix-7 XC7A100T) board top
//
//   CLK100MHZ  -> MMCM -> 50 MHz core clock (change CLKOUT0_DIVIDE to retime)
//   CPU_RESET  -> active-low reset, synchronised to the core clock
//   SW[15:0]   -> SWITCH register      LED[15:0] <- LED register
//   BTN C/U/L/R/D -> BUTTON register    7-segment <- SEVENSEG register (8 hex digits)
//
// Define SIM (iverilog -DSIM) to replace the MMCM with a direct clock.
module nexys4_top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire [15:0] SW,
    input  wire        BTNC, BTNU, BTNL, BTNR, BTND,
    output wire [15:0] LED,
    output wire [6:0]  SEG,        // CA..CG, active low
    output wire        DP,
    output wire [7:0]  AN          // active low
);
    // ------------------------------------------------------------------
    // Clock: 100 MHz in -> 50 MHz core (VCO = 1000 MHz)
    // ------------------------------------------------------------------
    wire clk, locked;
`ifdef SIM
    assign clk    = CLK100MHZ;
    assign locked = 1'b1;
`else
    wire clkfb, clk_mmcm;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (10.0),
        .CLKFBOUT_MULT_F (10.0),
        .DIVCLK_DIVIDE   (1),
        .CLKOUT0_DIVIDE_F(20.0)       // 1000/20 = 50 MHz ; 16.0 -> 62.5, 12.0 -> 83.3
    ) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk_mmcm), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG u_bufg (.I(clk_mmcm), .O(clk));
`endif

    // ------------------------------------------------------------------
    // Reset: asynchronous assert, synchronous release
    // ------------------------------------------------------------------
    reg [3:0] rst_sync;
    wire      rst_in_n = CPU_RESETN & locked;
    always @(posedge clk or negedge rst_in_n) begin
        if (!rst_in_n) rst_sync <= 4'b0000;
        else           rst_sync <= {rst_sync[2:0], 1'b1};
    end
    wire rst_n = rst_sync[3];

    // ------------------------------------------------------------------
    // Input synchronisers (2-flop) for switches and buttons
    // ------------------------------------------------------------------
    reg [20:0] in_s1, in_s2;
    always @(posedge clk) begin
        in_s1 <= {BTND, BTNR, BTNL, BTNU, BTNC, SW};
        in_s2 <= in_s1;
    end

    // ------------------------------------------------------------------
    // Processor
    // ------------------------------------------------------------------
    wire [31:0] sevenseg;
    rv32_soc #(
        .IMEM_INIT("imem.hex"),
        .DMEM_INIT("dmem.hex")
    ) u_soc (
        .clk(clk), .rst_n(rst_n),
        .sw(in_s2[15:0]), .btn(in_s2[20:16]),
        .led(LED), .sevenseg(sevenseg),
        .tohost(), .tohost_we()
    );

    // ------------------------------------------------------------------
    // 8-digit multiplexed 7-segment display
    // ------------------------------------------------------------------
    sevenseg_driver #(.CLK_HZ(50_000_000)) u_7seg (
        .clk(clk), .rst_n(rst_n), .value(sevenseg),
        .seg(SEG), .dp(DP), .an(AN)
    );
endmodule
