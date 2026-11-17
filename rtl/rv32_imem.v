// rv32_imem.v - synchronous instruction ROM (infers block RAM in Vivado)
// INIT_FILE is a $readmemh file with one 32-bit word per line.
module rv32_imem #(
    parameter WORDS     = 4096,             // 16 KB
    parameter INIT_FILE = "imem.hex"
)(
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] addr,                // byte address
    output reg  [31:0] rdata
);
    localparam AW = $clog2(WORDS);

    (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013; // NOP
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (en) rdata <= mem[addr[AW+1:2]];
    end
endmodule
