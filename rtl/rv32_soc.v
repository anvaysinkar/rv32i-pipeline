// rv32_soc.v - core + instruction ROM + data RAM + memory-mapped I/O
//
// Memory map
//   0x0000_0000 - 0x0000_3FFF  IMEM  16 KB  (instruction fetch only)
//   0x1000_0000 - 0x1000_3FFF  DMEM  16 KB  (load/store)
//   0x2000_0000                LED       W/R  [15:0]
//   0x2000_0004                SWITCH    R    [15:0]
//   0x2000_0008                SEVENSEG  W/R  [31:0]  8 hex digits
//   0x2000_000C                BUTTON    R    [4:0]  {D,R,L,U,C}
//   0x2000_0010                TOHOST    W    test pass/fail signature (sim)
//   0x2000_0014                CYCLES    R    free-running cycle counter
//   0x2000_0018                INSTRET   R    retired instruction counter
module rv32_soc #(
    parameter IMEM_WORDS = 4096,
    parameter DMEM_WORDS = 4096,
    parameter IMEM_INIT  = "imem.hex",
    parameter DMEM_INIT  = "dmem.hex"
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] sw,
    input  wire [4:0]  btn,
    output reg  [15:0] led,
    output reg  [31:0] sevenseg,
    output reg  [31:0] tohost,
    output reg         tohost_we
);
    wire [31:0] imem_addr, imem_rdata;
    wire        imem_en;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_be;
    wire        dmem_re, dmem_we, retire;

    rv32_core u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_en(imem_en), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
        .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .retire(retire)
    );

    rv32_imem #(.WORDS(IMEM_WORDS), .INIT_FILE(IMEM_INIT)) u_imem (
        .clk(clk), .en(imem_en), .addr(imem_addr), .rdata(imem_rdata)
    );

    // address decode (EX stage)
    wire sel_ram = (dmem_addr[31:28] == 4'h1);
    wire sel_io  = (dmem_addr[31:28] == 4'h2);

    wire [31:0] ram_rdata;
    rv32_dmem #(.WORDS(DMEM_WORDS), .INIT_FILE(DMEM_INIT)) u_dmem (
        .clk(clk), .en(sel_ram & (dmem_re | dmem_we)),
        .we(sel_ram ? dmem_be : 4'b0000),
        .addr(dmem_addr), .wdata(dmem_wdata), .rdata(ram_rdata)
    );

    // performance counters
    reg [31:0] cycles, instret;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cycles <= 32'd0; instret <= 32'd0; end
        else begin
            cycles  <= cycles + 32'd1;
            instret <= instret + {31'd0, retire};
        end
    end

    // I/O registers: write on the EX->MEM edge, read data registered on the same edge
    wire [3:0] io_reg = dmem_addr[5:2];
    reg  [31:0] io_rdata;
    reg         rd_sel_io;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 16'd0; sevenseg <= 32'd0; tohost <= 32'd0; tohost_we <= 1'b0;
            io_rdata <= 32'd0; rd_sel_io <= 1'b0;
        end else begin
            tohost_we <= 1'b0;
            rd_sel_io <= sel_io;
            if (sel_io && dmem_we) begin
                case (io_reg)
                    4'd0: led      <= dmem_wdata[15:0];
                    4'd2: sevenseg <= dmem_wdata;
                    4'd4: begin tohost <= dmem_wdata; tohost_we <= 1'b1; end
                    default: ;
                endcase
            end
            case (io_reg)
                4'd0:    io_rdata <= {16'd0, led};
                4'd1:    io_rdata <= {16'd0, sw};
                4'd2:    io_rdata <= sevenseg;
                4'd3:    io_rdata <= {27'd0, btn};
                4'd5:    io_rdata <= cycles;
                4'd6:    io_rdata <= instret;
                default: io_rdata <= 32'd0;
            endcase
        end
    end

    assign dmem_rdata = rd_sel_io ? io_rdata : ram_rdata;
endmodule
