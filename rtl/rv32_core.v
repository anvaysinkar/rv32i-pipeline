// rv32_core.v - 32-bit RISC-V (RV32I) 5-stage in-order pipeline
//
//   IF  -> ID  -> EX  -> MEM -> WB
//
// Hazard handling
//   * Data hazards: full forwarding from EX/MEM and MEM/WB into EX.
//     WB -> ID is handled by the write-through register file.
//   * Load-use: one-cycle stall (PC and IF/ID hold, bubble into ID/EX).
//   * Control: static not-taken. Branches, JAL and JALR resolve in EX;
//     a taken branch/jump flushes the two younger instructions (2-cycle penalty).
//
// Memory interface (both memories are synchronous, one-cycle read latency,
// which maps directly onto FPGA block RAM and ASIC SRAM macros)
//   * Instruction port: imem_addr is the PC register. The instruction comes
//     back on imem_rdata one cycle later, i.e. the memory's output register
//     acts as the instruction field of the IF/ID pipeline register.
//     imem_en is low during a stall so the memory holds its output.
//   * Data port: address, write data and byte enables are driven from the
//     EX stage. Writes happen and read data is registered on the EX->MEM
//     clock edge, so dmem_rdata is valid during the MEM stage.
`include "rv32_defs.vh"

module rv32_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,

    // instruction memory
    output wire [31:0] imem_addr,
    output wire        imem_en,
    input  wire [31:0] imem_rdata,

    // data memory
    output wire [31:0] dmem_addr,
    output wire        dmem_re,
    output wire        dmem_we,
    output wire [3:0]  dmem_be,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    // retire pulse (one per committed instruction) for performance counters
    output wire        retire
);
    // ------------------------------------------------------------------
    // Hazard / control signals (computed further down)
    // ------------------------------------------------------------------
    wire        stall;          // load-use stall: hold PC and IF/ID
    wire        flush;          // taken branch/jump in EX
    wire [31:0] redirect_pc;

    // ==================================================================
    // IF stage
    // ==================================================================
    reg  [31:0] pc_q;
    wire [31:0] pc_plus4 = pc_q + 32'd4;
    wire [31:0] pc_next  = flush ? redirect_pc :
                           stall ? pc_q        : pc_plus4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_q <= RESET_PC;
        else        pc_q <= pc_next;
    end

    assign imem_addr = pc_q;
    assign imem_en   = ~stall | flush;

    // IF/ID register (instruction itself lives in the memory output register)
    reg  [31:0] id_pc;
    reg         id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc    <= 32'd0;
            id_valid <= 1'b0;
        end else if (flush) begin
            id_valid <= 1'b0;
        end else if (!stall) begin
            id_pc    <= pc_q;
            id_valid <= 1'b1;
        end
    end

    // ==================================================================
    // ID stage
    // ==================================================================
    wire [31:0] id_inst = id_valid ? imem_rdata : `NOP_INST;

    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire [31:0] id_imm;
    wire [3:0]  id_alu_ctrl;
    wire [1:0]  id_a_sel, id_wb_sel;
    wire        id_b_imm, id_reg_write, id_mem_read, id_mem_write;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_uses_rs1, id_uses_rs2;

    rv32_decoder u_dec (
        .inst(id_inst), .rs1(id_rs1), .rs2(id_rs2), .rd(id_rd), .funct3(id_funct3),
        .imm(id_imm), .alu_ctrl(id_alu_ctrl), .a_sel(id_a_sel), .b_imm(id_b_imm),
        .reg_write(id_reg_write), .wb_sel(id_wb_sel), .mem_read(id_mem_read),
        .mem_write(id_mem_write), .is_branch(id_is_branch), .is_jal(id_is_jal),
        .is_jalr(id_is_jalr), .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2)
    );

    // WB-stage write port (declared here, driven in WB)
    wire        wb_we;
    wire [4:0]  wb_rd_w;
    wire [31:0] wb_data;

    wire [31:0] id_rs1_val, id_rs2_val;

    rv32_regfile u_rf (
        .clk(clk), .we(wb_we), .waddr(wb_rd_w), .wdata(wb_data),
        .raddr1(id_rs1), .rdata1(id_rs1_val),
        .raddr2(id_rs2), .rdata2(id_rs2_val)
    );

    // ID/EX register
    reg  [31:0] ex_pc, ex_rs1_val, ex_rs2_val, ex_imm;
    reg  [4:0]  ex_rs1, ex_rs2, ex_rd;
    reg  [2:0]  ex_funct3;
    reg  [3:0]  ex_alu_ctrl;
    reg  [1:0]  ex_a_sel, ex_wb_sel;
    reg         ex_b_imm, ex_reg_write, ex_mem_read, ex_mem_write;
    reg         ex_is_branch, ex_is_jal, ex_is_jalr, ex_valid;

    // load-use hazard: load in EX whose rd is a source of the instruction in ID
    assign stall = ex_valid && ex_mem_read && (ex_rd != 5'd0) &&
                   ((id_uses_rs1 && id_rs1 == ex_rd) ||
                    (id_uses_rs2 && id_rs2 == ex_rd));

    wire bubble = flush | stall | ~id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_valid <= 1'b0; ex_reg_write <= 1'b0; ex_mem_read <= 1'b0;
            ex_mem_write <= 1'b0; ex_is_branch <= 1'b0; ex_is_jal <= 1'b0;
            ex_is_jalr <= 1'b0;
            ex_pc <= 32'd0; ex_rs1_val <= 32'd0; ex_rs2_val <= 32'd0; ex_imm <= 32'd0;
            ex_rs1 <= 5'd0; ex_rs2 <= 5'd0; ex_rd <= 5'd0; ex_funct3 <= 3'd0;
            ex_alu_ctrl <= 4'd0; ex_a_sel <= 2'd0; ex_wb_sel <= 2'd0; ex_b_imm <= 1'b0;
        end else begin
            // datapath fields always load; only control is cleared on a bubble
            ex_pc       <= id_pc;
            ex_rs1_val  <= id_rs1_val;
            ex_rs2_val  <= id_rs2_val;
            ex_imm      <= id_imm;
            ex_rs1      <= id_uses_rs1 ? id_rs1 : 5'd0;
            ex_rs2      <= id_uses_rs2 ? id_rs2 : 5'd0;
            ex_rd       <= id_rd;
            ex_funct3   <= id_funct3;
            ex_alu_ctrl <= id_alu_ctrl;
            ex_a_sel    <= id_a_sel;
            ex_b_imm    <= id_b_imm;
            ex_wb_sel   <= id_wb_sel;

            ex_valid     <= ~bubble;
            ex_reg_write <= ~bubble & id_reg_write;
            ex_mem_read  <= ~bubble & id_mem_read;
            ex_mem_write <= ~bubble & id_mem_write;
            ex_is_branch <= ~bubble & id_is_branch;
            ex_is_jal    <= ~bubble & id_is_jal;
            ex_is_jalr   <= ~bubble & id_is_jalr;
        end
    end

    // ==================================================================
    // EX stage
    // ==================================================================
    // EX/MEM and MEM/WB registers (declared early for forwarding)
    reg  [31:0] mem_result, mem_pc;
    reg  [4:0]  mem_rd;
    reg  [2:0]  mem_funct3;
    reg  [1:0]  mem_addr_lo;
    reg  [1:0]  mem_wb_sel;
    reg         mem_reg_write, mem_valid;

    reg  [31:0] wb_result;
    reg  [4:0]  wb_rd;
    reg         wb_reg_write, wb_valid;

    // Forwarding unit. Priority: newest value (EX/MEM) first.
    // A load in MEM never needs forwarding here because of the load-use stall.
    wire fwd_a_mem = mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs1);
    wire fwd_a_wb  = wb_reg_write  && (wb_rd  != 5'd0) && (wb_rd  == ex_rs1);
    wire fwd_b_mem = mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs2);
    wire fwd_b_wb  = wb_reg_write  && (wb_rd  != 5'd0) && (wb_rd  == ex_rs2);

    wire [31:0] rs1_fwd = fwd_a_mem ? mem_result : fwd_a_wb ? wb_data : ex_rs1_val;
    wire [31:0] rs2_fwd = fwd_b_mem ? mem_result : fwd_b_wb ? wb_data : ex_rs2_val;

    wire [31:0] alu_a = (ex_a_sel == `ASEL_PC)   ? ex_pc :
                        (ex_a_sel == `ASEL_ZERO) ? 32'd0 : rs1_fwd;
    wire [31:0] alu_b = ex_b_imm ? ex_imm : rs2_fwd;
    wire [31:0] alu_y;

    rv32_alu u_alu (.a(alu_a), .b(alu_b), .alu_ctrl(ex_alu_ctrl), .y(alu_y));

    // Branch unit
    wire eq  = (rs1_fwd == rs2_fwd);
    wire lt  = ($signed(rs1_fwd) < $signed(rs2_fwd));
    wire ltu = (rs1_fwd < rs2_fwd);
    reg  br_cond;
    always @(*) begin
        case (ex_funct3)
            3'b000:  br_cond = eq;    // BEQ
            3'b001:  br_cond = ~eq;   // BNE
            3'b100:  br_cond = lt;    // BLT
            3'b101:  br_cond = ~lt;   // BGE
            3'b110:  br_cond = ltu;   // BLTU
            3'b111:  br_cond = ~ltu;  // BGEU
            default: br_cond = 1'b0;
        endcase
    end

    wire [31:0] br_target   = ex_pc + ex_imm;
    wire [31:0] jalr_target = (rs1_fwd + ex_imm) & ~32'd1;

    assign flush       = (ex_is_branch & br_cond) | ex_is_jal | ex_is_jalr;
    assign redirect_pc = ex_is_jalr ? jalr_target : br_target;

    wire [31:0] ex_pc4    = ex_pc + 32'd4;
    wire [31:0] ex_result = (ex_wb_sel == `WB_PC4) ? ex_pc4 : alu_y;

    // Store data alignment and byte enables (driven from EX, memory is sync)
    reg [3:0]  st_be;
    reg [31:0] st_data;
    always @(*) begin
        case (ex_funct3[1:0])
            2'b00: begin // SB
                st_data = {4{rs2_fwd[7:0]}};
                st_be   = 4'b0001 << alu_y[1:0];
            end
            2'b01: begin // SH
                st_data = {2{rs2_fwd[15:0]}};
                st_be   = alu_y[1] ? 4'b1100 : 4'b0011;
            end
            default: begin // SW
                st_data = rs2_fwd;
                st_be   = 4'b1111;
            end
        endcase
    end

    assign dmem_addr  = alu_y;
    assign dmem_re    = ex_mem_read;
    assign dmem_we    = ex_mem_write;
    assign dmem_be    = ex_mem_write ? st_be : 4'b0000;
    assign dmem_wdata = st_data;

    // EX/MEM register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_valid <= 1'b0; mem_reg_write <= 1'b0;
            mem_result <= 32'd0; mem_pc <= 32'd0; mem_rd <= 5'd0;
            mem_funct3 <= 3'd0; mem_addr_lo <= 2'd0; mem_wb_sel <= 2'd0;
        end else begin
            mem_valid     <= ex_valid;
            mem_reg_write <= ex_reg_write;
            mem_result    <= ex_result;
            mem_pc        <= ex_pc;
            mem_rd        <= ex_rd;
            mem_funct3    <= ex_funct3;
            mem_addr_lo   <= alu_y[1:0];
            mem_wb_sel    <= ex_wb_sel;
        end
    end

    // ==================================================================
    // MEM stage: load data extraction
    // ==================================================================
    wire [31:0] ld_shift = dmem_rdata >> {mem_addr_lo, 3'b000};
    reg  [31:0] ld_data;
    always @(*) begin
        case (mem_funct3)
            3'b000:  ld_data = {{24{ld_shift[7]}},  ld_shift[7:0]};   // LB
            3'b001:  ld_data = {{16{ld_shift[15]}}, ld_shift[15:0]};  // LH
            3'b100:  ld_data = {24'd0, ld_shift[7:0]};                // LBU
            3'b101:  ld_data = {16'd0, ld_shift[15:0]};               // LHU
            default: ld_data = dmem_rdata;                            // LW
        endcase
    end

    wire [31:0] mem_final = (mem_wb_sel == `WB_MEM) ? ld_data : mem_result;

    // MEM/WB register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_valid <= 1'b0; wb_reg_write <= 1'b0; wb_rd <= 5'd0; wb_result <= 32'd0;
        end else begin
            wb_valid     <= mem_valid;
            wb_reg_write <= mem_reg_write;
            wb_rd        <= mem_rd;
            wb_result    <= mem_final;
        end
    end

    // ==================================================================
    // WB stage
    // ==================================================================
    assign wb_we   = wb_reg_write;
    assign wb_rd_w = wb_rd;
    assign wb_data = wb_result;
    assign retire  = wb_valid;

endmodule
