// rv32_decoder.v - instruction decode and immediate generation (ID stage)
// FENCE, ECALL, EBREAK and CSR instructions are decoded as NOPs; this core
// has no privileged architecture. Unknown opcodes are also NOPs.
`include "rv32_defs.vh"

module rv32_decoder (
    input  wire [31:0] inst,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output reg  [31:0] imm,
    output reg  [3:0]  alu_ctrl,
    output reg  [1:0]  a_sel,
    output reg         b_imm,      // 1: ALU operand B = imm, 0: rs2
    output reg         reg_write,
    output reg  [1:0]  wb_sel,
    output reg         mem_read,
    output reg         mem_write,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         uses_rs1,
    output reg         uses_rs2
);
    wire [6:0] opcode = inst[6:0];
    wire [6:0] funct7 = inst[31:25];

    assign rs1    = inst[19:15];
    assign rs2    = inst[24:20];
    assign rd     = inst[11:7];
    assign funct3 = inst[14:12];

    // Immediate formats
    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'd0};
    wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    always @(*) begin
        // defaults = NOP
        imm       = imm_i;
        alu_ctrl  = 4'b0000;
        a_sel     = `ASEL_RS1;
        b_imm     = 1'b1;
        reg_write = 1'b0;
        wb_sel    = `WB_ALU;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        is_branch = 1'b0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;

        case (opcode)
            `OP_LUI: begin
                imm = imm_u; a_sel = `ASEL_ZERO; reg_write = 1'b1;
            end
            `OP_AUIPC: begin
                imm = imm_u; a_sel = `ASEL_PC; reg_write = 1'b1;
            end
            `OP_JAL: begin
                imm = imm_j; is_jal = 1'b1; reg_write = 1'b1; wb_sel = `WB_PC4;
            end
            `OP_JALR: begin
                imm = imm_i; is_jalr = 1'b1; reg_write = 1'b1; wb_sel = `WB_PC4;
                uses_rs1 = 1'b1;
            end
            `OP_BRANCH: begin
                imm = imm_b; is_branch = 1'b1; b_imm = 1'b0;
                uses_rs1 = 1'b1; uses_rs2 = 1'b1;
            end
            `OP_LOAD: begin
                imm = imm_i; mem_read = 1'b1; reg_write = 1'b1; wb_sel = `WB_MEM;
                uses_rs1 = 1'b1;
            end
            `OP_STORE: begin
                imm = imm_s; mem_write = 1'b1;
                uses_rs1 = 1'b1; uses_rs2 = 1'b1;
            end
            `OP_IMM: begin
                imm = imm_i; reg_write = 1'b1; uses_rs1 = 1'b1;
                // only SRAI uses funct7[5]; ADDI has no SUB form
                alu_ctrl = {(funct3 == 3'b101) & funct7[5], funct3};
            end
            `OP_REG: begin
                b_imm = 1'b0; reg_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
                alu_ctrl = {funct7[5], funct3};
            end
            default: ; // FENCE / SYSTEM / illegal -> NOP
        endcase
    end
endmodule
