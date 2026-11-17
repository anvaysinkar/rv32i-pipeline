// rv32_dmem.v - synchronous data RAM with byte write enables
// Written in the Xilinx byte-write block RAM template (read-first).
module rv32_dmem #(
    parameter WORDS     = 4096,             // 16 KB
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        en,
    input  wire [3:0]  we,                  // byte enables
    input  wire [31:0] addr,                // byte address
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    localparam AW = $clog2(WORDS);

    (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    wire [AW-1:0] a = addr[AW+1:2];

    always @(posedge clk) begin
        if (en) begin
            if (we[0]) mem[a][7:0]   <= wdata[7:0];
            if (we[1]) mem[a][15:8]  <= wdata[15:8];
            if (we[2]) mem[a][23:16] <= wdata[23:16];
            if (we[3]) mem[a][31:24] <= wdata[31:24];
            rdata <= mem[a];
        end
    end
endmodule
