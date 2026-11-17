// sevenseg_driver.v - time-multiplexed driver for the Nexys4 8-digit display
// Shows 'value' as 8 hex digits. Segments and anodes are active low.
module sevenseg_driver #(
    parameter CLK_HZ   = 50_000_000,
    parameter REFRESH  = 1000            // digit refresh rate in Hz (whole display = /8)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] value,
    output reg  [6:0]  seg,             // {g,f,e,d,c,b,a} -> SEG[6:0] = CG..CA
    output wire        dp,
    output reg  [7:0]  an
);
    localparam DIV = CLK_HZ / (REFRESH * 8);

    reg [$clog2(DIV)-1:0] cnt;
    reg [2:0]             digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0; digit <= 3'd0;
        end else if (cnt == DIV - 1) begin
            cnt <= 0; digit <= digit + 3'd1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    wire [3:0] nib = value >> {digit, 2'b00};

    always @(*) begin
        an = ~(8'b0000_0001 << digit);
        case (nib)                       // gfedcba, active low
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            default: seg = 7'b0001110;  // F
        endcase
    end

    assign dp = 1'b1;   // decimal points off
endmodule
