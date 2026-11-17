# rv32i-pipeline

A 32-bit RISC-V (RV32I) processor with a classic 5-stage pipeline, written in synthesisable Verilog-2001. It targets the Digilent Nexys4 / Nexys4 DDR (Artix-7) in AMD Vivado, and has scripts for an RTL-to-GDSII run in three flows:

- LibreLane on SkyWater 130 nm (open source)
- Cadence: Genus, Innovus, Tempus, Conformal
- Synopsys: DC, ICC2, PrimeTime, Formality

```
 IF ──► ID ──► EX ──► MEM ──► WB
        ▲      │ ▲     │
        └flush─┘ └─fwd─┴── EX/MEM and MEM/WB forwarding
```

- **Pipeline:** IF / ID / EX / MEM / WB with full forwarding. A load-use hazard costs one stall cycle. Branches and jumps resolve in EX with static not-taken prediction, so a taken branch costs 2 cycles.
- **Memories:** synchronous instruction and data memories (block RAM on the FPGA, SRAM macros on silicon), with byte enables on stores.
- **Memory-mapped I/O:** LEDs, switches, buttons, the 8-digit 7-segment display, and cycle and instret counters.
- **ISA scope:** RV32I base integer, all 37 computational, load/store, branch and jump instructions. FENCE, ECALL, EBREAK and CSR instructions decode as NOPs, since there are no traps or interrupts.

## Verification

All 40 applicable `rv32ui` tests from [riscv-tests](https://github.com/riscv-software-src/riscv-tests) pass on the RTL in Icarus Verilog. `fence_i` and `ma_data` are left out: the first needs self-modifying code, which a separate IMEM can't support, and the second needs misaligned-access traps.

| Test group | CPI |
|---|---|
| ALU / load / store tests | 1.08 – 1.11 |
| Branch tests | 1.21 – 1.28 |
| C demo on the full Nexys4 top (simulated) | 1.45 |

```bash
sim/run_riscv_tests.sh      # clones riscv-tests, builds each test, runs it on tb_soc.v
sim/run_board_sim.sh        # runs the C demo on the full board top (MMCM bypassed)
```

Requirements: `riscv64-unknown-elf-gcc`, `iverilog`, `python3`.

## FPGA (Nexys4)

```bash
make -C sw/demo                                        # build the demo -> imem.hex / dmem.hex
cd fpga && vivado -mode batch -source build.tcl        # Nexys4
cd fpga && vivado -mode batch -source build.tcl -tclargs nexys4_ddr   # Nexys4 DDR / A7-100T
```

`fpga/create_project.tcl` builds a Vivado GUI project instead. The demo shows a counter on the 7-segment display and the CPI when you hold BTND. Pinouts and what to expect on the board are in the [guide](docs/GUIDE.md#4-fpga-implementation-on-the-nexys4).

## ASIC flow

| Folder | Flow |
|---|---|
| `asic/constraints/rv32_core.sdc` | Constraints shared by every flow (20 ns clock) |
| `asic/openlane/config.json` | LibreLane, sky130A, `sky130_fd_sc_hd` |
| `asic/cadence/` | Genus synthesis → Conformal LEC → Innovus P&R → Tempus STA |
| `asic/synopsys/` | DC synthesis → Formality → ICC2 P&R → PrimeTime |

**Status:** these scripts are written but have not yet been run end to end. A tapeout-style run will need PDK paths and library cell names filled in for the kit you have. Section 6 onward of the guide walks through each flow.

## Layout

```
rtl/      rv32_core.v (pipeline, hazards, forwarding), alu, decoder, regfile, imem, dmem, soc
sim/      tb_soc.v (self-checking, TOHOST), tb_nexys4_top.v, test scripts
sw/       linker script, crt0, C demo, riscv-tests environment, elf2hex
fpga/     Nexys4 top, 7-segment driver, XDC for both boards, Vivado build scripts
asic/     SDC, LibreLane, Cadence and Synopsys scripts
docs/     GUIDE.md: microarchitecture, simulation, FPGA and ASIC walkthrough
```

## Credits

Course project for Digital IC Design at Vishwakarma Institute of Technology, Pune, by Anvay Sinkar, Viyan Shetty and Aaryan Shinde, guided by Prof. Ketan Raut.
