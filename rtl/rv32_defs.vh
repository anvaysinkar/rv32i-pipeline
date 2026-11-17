// rv32_defs.vh - shared constants for the RV32I pipeline
`ifndef RV32_DEFS_VH
`define RV32_DEFS_VH

// Major opcodes (inst[6:0])
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_IMM      7'b0010011
`define OP_REG      7'b0110011
`define OP_FENCE    7'b0001111
`define OP_SYSTEM   7'b1110011

// ALU operand A select
`define ASEL_RS1    2'd0
`define ASEL_PC     2'd1
`define ASEL_ZERO   2'd2

// Write-back select
`define WB_ALU      2'd0
`define WB_MEM      2'd1
`define WB_PC4      2'd2

// Canonical NOP: addi x0, x0, 0
`define NOP_INST    32'h0000_0013

`endif
