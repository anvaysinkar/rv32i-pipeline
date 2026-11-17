// rv32_regfile.v - 32 x 32-bit register file, 2 read ports, 1 write port
// x0 is hard-wired to zero. A write and a read of the same register in the
// same cycle returns the new value (write-through bypass), which removes the
// WB -> ID hazard from the pipeline.
module rv32_regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2
);
    reg [31:0] regs [1:31];

    always @(posedge clk) begin
        if (we && waddr != 5'd0)
            regs[waddr] <= wdata;
    end

    wire bypass1 = we && (waddr != 5'd0) && (waddr == raddr1);
    wire bypass2 = we && (waddr != 5'd0) && (waddr == raddr2);

    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : bypass1 ? wdata : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : bypass2 ? wdata : regs[raddr2];
endmodule
