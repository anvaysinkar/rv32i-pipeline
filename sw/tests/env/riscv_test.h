// riscv_test.h - minimal bare-metal test environment for the riscv-tests
// rv32ui suite on this core (no CSRs, no traps).
// Pass/fail is reported by storing to the TOHOST register at 0x2000_0010:
//   1                -> pass
//   (testnum<<1) | 1 -> fail in test number testnum
#ifndef _ENV_RV32_PIPELINE_H
#define _ENV_RV32_PIPELINE_H

#define RVTEST_RV64U  .macro init; .endm
#define RVTEST_RV32U  .macro init; .endm

#define TESTNUM gp
#define TOHOST_ADDR 0x20000010

#define RVTEST_CODE_BEGIN        \
        .section .text.init;     \
        .align  2;               \
        .globl _start;           \
_start:                          \
        li  TESTNUM, 0;          \
        init;

#define RVTEST_CODE_END          \
1:      j 1b;

#define RVTEST_PASS              \
        fence;                   \
        li  TESTNUM, 1;          \
        li  t6, TOHOST_ADDR;     \
        sw  TESTNUM, 0(t6);      \
2:      j 2b;

#define RVTEST_FAIL              \
        fence;                   \
1:      beqz TESTNUM, 1b;        \
        sll  TESTNUM, TESTNUM, 1; \
        or   TESTNUM, TESTNUM, 1; \
        li   t6, TOHOST_ADDR;    \
        sw   TESTNUM, 0(t6);     \
3:      j 3b;

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN EXTRA_DATA .align 4;
#define RVTEST_DATA_END

#endif
