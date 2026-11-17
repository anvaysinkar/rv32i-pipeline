# RV32I 5-stage pipeline: from RTL to a Nexys4 bitstream and to GDSII

This guide goes with the `rv32i_pipeline` project. It covers three things:

1. How the processor is built and how to check it in simulation.
2. How to put it on a Digilent Nexys4 (Artix-7 XC7A100T) with AMD Vivado.
3. How to take the same core through an RTL-to-GDSII flow, once with open-source tools (LibreLane/OpenROAD on SkyWater 130 nm) and once each with the Cadence and Synopsys tools available through the C2S programme.

Status: the RTL and software are verified in simulation. The core passes all 40 applicable tests of the official `rv32ui` suite from riscv-tests, and the full board top runs the demo program in simulation. The Vivado project builds and simulates the board top in xsim. The Cadence, Synopsys and LibreLane scripts have not been run end to end yet, so expect to fix a path or a library cell name on a first run. The places where that is likely are called out below.

---

## 1. Project layout

```
rv32i_pipeline/
├── rtl/                  processor RTL (synthesisable Verilog-2001)
│   ├── rv32_defs.vh        opcodes and select encodings
│   ├── rv32_alu.v          ALU
│   ├── rv32_regfile.v      32x32 register file, write-through
│   ├── rv32_decoder.v      decode + immediate generation
│   ├── rv32_core.v         the 5-stage pipeline (hazards, forwarding, branches)
│   ├── rv32_imem.v         instruction ROM (block RAM)
│   ├── rv32_dmem.v         data RAM with byte enables (block RAM)
│   └── rv32_soc.v          core + memories + memory-mapped I/O
├── sim/
│   ├── tb_soc.v            self-checking testbench (pass/fail via TOHOST)
│   ├── tb_nexys4_top.v     board-level testbench
│   ├── run_riscv_tests.sh  builds and runs the rv32ui ISA tests
│   └── run_board_sim.sh    runs the demo on the full board top
├── sw/
│   ├── link.ld             Harvard memory map for the linker
│   ├── elf2hex.py          binary -> $readmemh file
│   ├── tests/env/          bare-metal environment for riscv-tests
│   └── demo/               C demo for the board (crt0.S, demo.c, Makefile)
├── fpga/
│   ├── nexys4/             board top, 7-seg driver, XDC for Nexys4 and Nexys4 DDR
│   ├── build.tcl           Vivado batch flow (RTL -> bitstream + reports)
│   └── create_project.tcl  builds a Vivado GUI project
└── asic/
    ├── constraints/        rv32_core.sdc (shared by every ASIC flow)
    ├── openlane/           LibreLane config.json
    ├── cadence/            Genus, Innovus, Tempus, Conformal scripts
    └── synopsys/           DC, ICC2, PrimeTime, Formality scripts
```

---

## 2. The microarchitecture

### 2.1 ISA support

RV32I base integer ISA: all 37 computational, load/store, branch and jump instructions. FENCE, ECALL, EBREAK and CSR instructions decode as NOPs, because there is no privileged architecture (no traps, no interrupts). That is the usual scope for a first pipelined core and it is what the `rv32ui` tests check.

### 2.2 Pipeline

```
        +------+     +------+     +------+     +------+     +------+
 PC --> |  IF  | --> |  ID  | --> |  EX  | --> | MEM  | --> |  WB  |
        +------+     +------+     +------+     +------+     +------+
        IMEM addr    decode,      ALU,         load data    register
        = PC reg     reg read,    branch,      align/sign   write
                     hazard det.  dmem addr                 
                         ^            |  ^  ^       |            |
                         |   flush    |  |  |       |            |
                         +------------+  |  +-------+ EX/MEM fwd |
                         (taken branch)  +-------------------------+ MEM/WB fwd
```

| Stage | What happens | Pipeline register after it |
|---|---|---|
| IF | PC register drives the instruction memory address | IF/ID: `id_pc`, `id_valid` (the instruction sits in the memory's output register) |
| ID | Decode, immediate generation, register file read, load-use check | ID/EX |
| EX | Forwarding muxes, ALU, branch compare, branch/jump target, store data alignment, data memory address | EX/MEM |
| MEM | Synchronous data memory returns read data; sign/zero extension for LB/LH/LBU/LHU | MEM/WB |
| WB | Register file write | none |

### 2.3 Hazards

Data hazards are handled by forwarding from EX/MEM and MEM/WB into the EX stage (`rs1_fwd`, `rs2_fwd` in `rv32_core.v`). The newer value wins. The register file passes a value being written straight through to a read of the same register in the same cycle, so the WB-to-ID case needs no extra logic.

A load followed directly by an instruction that uses the loaded register cannot be covered by forwarding, because the data only exists at the end of MEM. The hazard unit detects this in ID, freezes PC and IF/ID for one cycle and puts a bubble into ID/EX. One cycle later the load is in WB and the value is forwarded from there.

Control hazards use static not-taken prediction. Branches, JAL and JALR resolve in EX. A taken branch or any jump redirects the PC and kills the two younger instructions in IF and ID, so the penalty is two cycles. The CPI figures from the test runs (1.08 on ALU-heavy tests, 1.2 to 1.3 on branch tests, 1.45 on the C demo) follow from this.

### 2.4 Why the memories are synchronous

Both memories have a one-cycle read latency. That matches FPGA block RAM and ASIC SRAM macros, so the same core works in both flows without changes.

- Instruction side: the PC register is the address. The instruction comes back in the next cycle, which is the ID stage, so the block RAM's output register doubles as the instruction field of IF/ID. During a stall the memory enable drops and the output holds.
- Data side: the address, write data and byte enables are driven from EX. The write and the registered read both happen on the EX-to-MEM clock edge, so load data is available in MEM. Because EX/MEM never stalls in this design, this is safe.

### 2.5 Memory map

| Address | Name | Access | Notes |
|---|---|---|---|
| `0x0000_0000` to `0x0000_3FFF` | IMEM | fetch only | 16 KB, loaded from `imem.hex` |
| `0x1000_0000` to `0x1000_3FFF` | DMEM | load/store | 16 KB, loaded from `dmem.hex` (.data/.rodata/.bss) |
| `0x2000_0000` | LED | R/W | bits [15:0] drive the 16 LEDs |
| `0x2000_0004` | SWITCH | R | 16 slide switches |
| `0x2000_0008` | SEVENSEG | R/W | 8 hex digits on the display |
| `0x2000_000C` | BUTTON | R | {BTND, BTNR, BTNL, BTNU, BTNC} |
| `0x2000_0010` | TOHOST | W | test result (simulation) |
| `0x2000_0014` | CYCLES | R | cycle counter |
| `0x2000_0018` | INSTRET | R | retired instruction counter |

It is a Harvard layout: loads cannot read IMEM. The linker script therefore places `.rodata` in DMEM along with `.data`.

---

## 3. Simulate first

Do this before touching Vivado. If the core is wrong, a bitstream just hides the problem.

### 3.1 Tools (Ubuntu, or WSL on Windows)

```bash
sudo apt install iverilog gtkwave gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf git python3
```

The `riscv64-unknown-elf` compiler builds 32-bit code fine with `-march=rv32i -mabi=ilp32`. If you have a `riscv32-unknown-elf` toolchain instead, run the scripts with `CROSS=riscv32-unknown-elf-`.

### 3.2 ISA compliance tests

```bash
cd rv32i_pipeline
sim/run_riscv_tests.sh            # all tests
sim/run_riscv_tests.sh add beq lw # a few
```

The script clones riscv-tests into `sim/build/`, compiles each `rv32ui` test against `sw/tests/env/riscv_test.h` (which reports results by writing to TOHOST instead of using CSRs), turns the ELF into `imem.hex`/`dmem.hex` and runs the testbench. Expected end of output:

```
xor      PASS  cycles=486 instret=450 CPI=1.080
xori     PASS  cycles=188 instret=170 CPI=1.106
----------------------------------------
passed: 40   failed: 0
```

`fence_i` (self-modifying code) and `ma_data` (misaligned access traps) are skipped because this core can't support them by design.

To look at waveforms for one test:

```bash
cd sim/build/beq && vvp -n ../tb_soc.vvp +vcd && gtkwave tb_soc.vcd
```

Good signals to add: `pc_q`, `id_pc`, `id_valid`, `ex_pc`, `stall`, `flush`, `fwd_a_mem`, `fwd_a_wb`, `alu_y`, `wb_rd`, `wb_data`. Watching `stall` and `flush` against the instruction stream is the fastest way to understand the pipeline.

### 3.3 Board-level simulation

```bash
sim/run_board_sim.sh
```

This builds the demo with a tiny clock constant so that time moves quickly, simulates `nexys4_top` with the MMCM bypassed (`-DSIM`), prints the LED and display state, and then rebuilds the demo for the real 50 MHz clock so the hex files are ready for Vivado.

You can also simulate in Vivado: `create_project.tcl` adds both testbenches to `sim_1` with `SIM` defined. Copy `imem.hex` and `dmem.hex` into the simulation run directory (`vivado_proj/rv32_nexys4.sim/sim_1/behav/xsim/`) if xsim complains that it can't open them.

---

## 4. FPGA implementation on the Nexys4

### 4.1 Which board do you have?

There are two boards sold as "Nexys4" with different pinouts:

- Original Nexys4 (16 MB CellularRAM, no DDR2 chip): use `fpga/nexys4/nexys4.xdc`.
- Nexys4 DDR, later renamed Nexys A7-100T (has a DDR2 chip, the board name says "DDR" or "A7"): use `fpga/nexys4/nexys4_ddr.xdc`.

Both use the XC7A100T-1CSG324C, so the part is `xc7a100tcsg324-1` either way. The pin numbers in both XDC files were taken from Digilent's master XDC files. If the wrong file is used, the design still builds but switches and LEDs won't respond.

### 4.2 What goes onto the FPGA

```
CLK100MHZ ──> MMCM ──> 50 MHz ──┬──> rv32_soc ─────────────┬──> LED[15:0]
CPU_RESETN ──> reset synchroniser┘     │                     └──> sevenseg_driver ──> SEG, AN
SW[15:0], BTNx ──> 2-flop synchronisers ┘
```

| Block | File | Maps to |
|---|---|---|
| Clocking | `nexys4_top.v` (MMCME2_BASE + BUFG) | 1 MMCM |
| Reset synchroniser, input synchronisers | `nexys4_top.v` | flip-flops |
| Pipeline core | `rv32_core.v` | about 1,200 LUTs, 500 flip-flops |
| Register file | `rv32_regfile.v` | distributed RAM (RAM32M) |
| IMEM, DMEM (16 KB each) | `rv32_imem.v`, `rv32_dmem.v` | 8 x RAMB36 equivalent |
| 7-segment multiplexer | `sevenseg_driver.v` | a few LUTs |

The resource numbers come from a Yosys `synth_xilinx` run on the SoC. Vivado's numbers will differ a little. Either way it is around 2 % of the XC7A100T.

The core runs at 50 MHz by default. That leaves margin for the long path from the forwarding muxes through the ALU into the branch compare, the PC mux and the block RAM address. After you have a working build, read the timing report and try 62.5 MHz (`CLKOUT0_DIVIDE_F(16.0)`) or 83.3 MHz (`12.0`). Change `CORE_HZ` in `sw/demo/demo.c` to match so the counter speed stays right.

### 4.3 Build the program

```bash
make -C sw/demo
```

This produces `sw/demo/imem.hex` and `sw/demo/dmem.hex`. The block RAMs are initialised from these files at synthesis time, so any change to the software means re-running synthesis (step 4.4).

### 4.4a Build with the Vivado GUI

1. Open Vivado. In the Tcl console at the bottom: `cd <path>/rv32i_pipeline/fpga`, then `source create_project.tcl`. For the DDR board, run `set argv nexys4_ddr` first.
2. Open `fpga/vivado_proj/rv32_nexys4.xpr` if it didn't open on its own. Check in the Sources window that `nexys4_top` is the top (bold) and that the two `.hex` files are listed as Memory Initialization Files.
3. Flow Navigator → Run Simulation → Run Behavioral Simulation. Let it run for about 700 µs (`run 700us`) and check that `LED` moves and `u_soc/sevenseg` has `beef` in the top half.
4. Flow Navigator → Run Synthesis. Afterwards open the synthesized design and check Report Utilization: you should see block RAM tiles for IMEM/DMEM. If you see a huge LUT count instead, the memories were not inferred as block RAM, usually because a `.hex` file could not be found.
5. Run Implementation. Open Report Timing Summary. WNS (worst negative slack) must be positive. If it isn't, lower the clock (section 4.2).
6. Generate Bitstream.
7. Connect the board over the PROG/UART micro-USB port and switch it on. Open Hardware Manager → Open Target → Auto Connect → Program Device, and pick `rv32_nexys4.bit`.

### 4.4b Build in batch mode

```bash
cd fpga
vivado -mode batch -source build.tcl                       # Nexys4
vivado -mode batch -source build.tcl -tclargs nexys4_ddr   # Nexys4 DDR
```

Outputs go to `fpga/out/`: `rv32_nexys4.bit`, `util_route.rpt`, `timing_route.rpt`, `power.rpt` and checkpoints. The script prints the worst slack at the end.

### 4.5 What you should see on the board

- The right four 7-segment digits count up about 10 times a second (hex).
- The left four digits show the switch setting in hex. Flip a switch and watch them change.
- One LED bounces left and right.
- Hold BTNU: the counter speeds up 4x. Press BTNC: it resets to zero.
- Hold BTND: the right four digits show the measured CPI x 100 in decimal (for example `0145` means 1.45 cycles per instruction).
- CPU_RESET restarts the program.

If nothing lights up, check in this order: right XDC for your board, the DONE LED is on after programming, the MMCM lock (probe `locked` with an ILA), and that `imem.hex` reached synthesis (search the synthesis log for `readmemh` warnings or errors).

### 4.6 Keeping the design in flash

So the board boots the processor at power-up:

1. In Hardware Manager, right-click the FPGA → Add Configuration Memory Device. Both boards carry a 128 Mbit Spansion S25FL128S, so pick `s25fl128sxxxxxx0-spi-x1_x2_x4`.
2. Generate a configuration file: `write_cfgmem -format mcs -size 16 -interface SPIx4 -loadbit {up 0x0 out/rv32_nexys4.bit} -file out/rv32_nexys4.mcs`.
3. Program the flash with the `.mcs` file and set the MODE jumper to QSPI.

### 4.7 Debugging on hardware

Mark signals in the RTL with `(* mark_debug = "true" *)`, for example `pc_q`, `stall`, `flush` and `wb_data` in `rv32_core.v`. After synthesis, run Tools → Set Up Debug to insert an ILA, then implement and program as usual. Hardware Manager will show a waveform window that triggers on any condition you set, such as `pc_q == 32'h0000_0100`.

---

## 5. RTL to GDSII: the flow in general

An FPGA build maps your logic onto fabric that already exists. An ASIC flow builds the transistors and wires themselves, so there are more steps and more things to check before the layout can be manufactured.

| # | Step | What it produces / checks | Open source | Cadence | Synopsys |
|---|---|---|---|---|---|
| 1 | RTL functional simulation | design does what the spec says | Icarus, Verilator | Xcelium | VCS |
| 2 | Lint | coding problems, latches, width mismatches | Verilator `--lint-only` | HAL / Jasper Superlint | SpyGlass |
| 3 | Logic synthesis | gate-level netlist in standard cells | Yosys + ABC | Genus | Design Compiler / Fusion Compiler |
| 4 | Equivalence check | netlist == RTL | Yosys `eqy` (limited) | Conformal LEC | Formality |
| 5 | Floorplan | die/core size, rows, pin positions | OpenROAD | Innovus | ICC2 |
| 6 | Power planning | VDD/VSS rings, stripes, rails | OpenROAD (pdngen) | Innovus | ICC2 |
| 7 | Placement | cells placed, pre-CTS optimisation | OpenROAD (RePlAce) | Innovus | ICC2 `place_opt` |
| 8 | Clock tree synthesis | balanced clock network | OpenROAD (TritonCTS) | Innovus CCOpt | ICC2 `clock_opt` |
| 9 | Routing | metal wires and vias | OpenROAD (TritonRoute) | Innovus NanoRoute | ICC2 Zroute |
| 10 | Parasitic extraction | R and C of every wire (SPEF) | OpenRCX | Quantus | StarRC |
| 11 | Signoff STA | setup/hold met in all corners | OpenSTA | Tempus | PrimeTime |
| 12 | Physical verification | DRC (layout rules), LVS (layout == netlist), antenna | Magic, KLayout, Netgen | Pegasus or PVS | IC Validator |
| 13 | GDSII | final layout file | KLayout / Magic | Innovus `streamOut`, Virtuoso | ICC2 `write_gds` |

What gets hardened here is `rv32_core` on its own, with the instruction and data memory buses as pins. On an FPGA the memories are block RAMs. On silicon they would be SRAM macros from a memory compiler (or OpenRAM / DFFRAM in the open-source world), placed next to the core in a later top-level run. Pushing 32 KB of memory through standard-cell synthesis would turn it into tens of thousands of flip-flops and swamp the flow, which is why the scripts leave it out.

All three flows read `asic/constraints/rv32_core.sdc`: a 20 ns clock (50 MHz), 0.25 ns uncertainty, input and output delays at 30 % of the period for the memory buses. It is plain SDC with literal numbers, so every tool parses it the same way. If you change the period, change the delays and `CLOCK_PERIOD` in `asic/openlane/config.json` with it.

---

## 6. Open-source flow: LibreLane on SkyWater 130 nm

OpenLane 2 is now developed under the name LibreLane. It drives Yosys, OpenROAD, OpenSTA, Magic, KLayout and Netgen in one flow and uses the open sky130A PDK by default.

### 6.1 Install (Ubuntu / WSL2)

Following the LibreLane Nix installation page:

```bash
sudo apt-get install -y curl git
curl --proto '=https' --tlsv1.2 -fsSL https://artifacts.nixos.org/nix-installer | sh -s -- install --no-confirm --extra-conf "
    extra-substituters = https://nix-cache.fossi-foundation.org
    extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
    extra-experimental-features = nix-command flakes
"
# close and reopen the terminal
git clone https://github.com/librelane/librelane
cd librelane
nix-shell                 # first time takes a while
librelane --smoke-test    # should finish without errors
```

There is also a Docker-based install if Nix doesn't work on your machine. The documentation has a separate page for it.

### 6.2 Run the core

Inside the `nix-shell`:

```bash
librelane ~/rv32i_pipeline/asic/openlane/config.json
```

The config points at the four core RTL files and the shared SDC, sets a 20 ns clock, 40 % core utilisation and 50 % placement density. The sky130A PDK and the `sky130_fd_sc_hd` library are the defaults. A run takes from several minutes to around half an hour depending on your machine.

### 6.3 Look at the result

```bash
librelane --last-run --flow openinklayout  ~/rv32i_pipeline/asic/openlane/config.json
librelane --last-run --flow openinopenroad ~/rv32i_pipeline/asic/openlane/config.json
```

The run directory `asic/openlane/runs/RUN_<date>/` holds a numbered folder per step and a `final/` folder with `gds/`, `def/`, `lef/`, `nl/` (netlists), `spef/`, `sdf/` and `metrics.json`.

Check these, in this order:

1. `final/metrics.json`: die area, cell count, worst setup/hold slack per corner, DRC/LVS/antenna error counts. All error counts should be zero.
2. The `*-openroad-stapostpnr/summary.rpt` file: setup and hold slack across corners. Negative setup slack means the 20 ns clock is too fast for this layout.
3. The Magic and KLayout DRC report folders (`*-magic-drc/`, `*-klayout-drc/`). Open the `.xml` files in KLayout with Tools → Marker Browser.
4. `netgen-lvs.log` in the LVS step folder should end with "Circuits match uniquely."
5. The `OpenROAD.CheckAntennas` step reports.

### 6.4 If something fails

- Setup violations: raise `CLOCK_PERIOD` and the SDC period together (try 25 ns), or look at the worst path report to see which stage limits you. It is usually the EX stage: forwarding mux → ALU → branch compare → PC mux.
- Hold violations after CTS are normally fixed by the flow itself. If they persist, the input delays in the SDC may be unrealistic.
- Placement or routing congestion: lower `FP_CORE_UTIL` to 30 and `PL_TARGET_DENSITY_PCT` to 40.
- Synthesis errors about includes: check that `VERILOG_INCLUDE_DIRS` points at `rtl/`.
- If the `dir::../../rtl/...` paths give trouble on your version, copy the four RTL files and `rv32_defs.vh` into `asic/openlane/src/` and point `VERILOG_FILES` at `dir::src/*.v`.

### 6.5 Gate-level simulation (optional but worth doing once)

Simulate the final netlist with the sky130 cell models to make sure synthesis didn't change behaviour. You need a small wrapper that instantiates `rv32_core` with the memory models from `rtl/`:

```bash
iverilog -DFUNCTIONAL -DUNIT_DELAY=#1 \
  $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
  $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v \
  runs/<run>/final/nl/rv32_core.nl.v  <your wrapper + tb>
```

---

## 7. Cadence flow (C2S / ChipIN tools)

Under C2S, the EDA tools are provided through the ChipIN centre and most colleges get them on a lab server. Source your lab's setup script first (often something like `source /cad/cshrc` or a `cadence.bashrc`) so that `xrun`, `genus`, `innovus`, `tempus` and `lec` are on your path.

### 7.1 Point the scripts at your PDK

Edit `asic/cadence/tech_setup.tcl` once. The defaults follow Cadence's generic 45 nm kit (GPDK045 with the GSCLIB045 standard cells), which is what most labs install for training. You need:

- slow and fast corner `.lib` files,
- technology LEF and cell LEF,
- a QRC tech file (or cap tables),
- the GDS layer map and the cell GDS,
- the core site name (`CoreSite` for GSCLIB045), the metal layer names and the filler cell names.

If your lab gives you the SCL 180 nm kit instead (the one used for C2S tape-outs), fill in the same variables from that kit. You will need to change the site name, layer names (the top metal will be lower) and filler cells. Look in the kit's cell LEF for `SITE` and the filler cell names, and in the tech LEF for layer names.

### 7.2 RTL simulation with Xcelium

```bash
cd sim/build/add            # any test folder made by run_riscv_tests.sh
xrun -64bit -access +rwc -incdir ../../../rtl \
     ../../../rtl/*.v ../../../sim/tb_soc.v -top tb_soc
```

Add `-gui` to open SimVision for waveforms.

### 7.3 Synthesis with Genus

```bash
cd asic/cadence
genus -files genus_syn.tcl -log logs/genus
```

The script reads the RTL, elaborates, checks the design, applies the SDC, runs `syn_generic`, `syn_map` and `syn_opt`, and writes:

- `outputs/rv32_core_syn.v`: gate-level netlist
- `outputs/rv32_core_syn.sdc`, `.sdf`
- `outputs/lec_rtl2syn.do`: a ready-made Conformal script
- `reports/`: `qor.rpt`, `timing.rpt`, `area.rpt`, `power.rpt`, `gates.rpt`

Read `reports/timing.rpt` first. The slack at the bottom of the worst path must be positive. `reports/check_design.rpt` should show no unresolved references or undriven pins.

To explore interactively, start `genus` and paste the script a section at a time. `gui_show` opens the schematic viewer.

### 7.4 Equivalence check with Conformal LEC

```bash
lec -XL -nogui -dofile outputs/lec_rtl2syn.do      # RTL vs synthesis netlist
lec -XL -nogui -dofile lec_rtl2pnr.do              # RTL vs routed netlist (after Innovus)
```

The report should say all compare points are equivalent. Edit the `.lib` path in `lec_rtl2pnr.do` to match your kit.

### 7.5 Place and route with Innovus

```bash
innovus -files innovus_pnr.tcl -log logs/innovus
```

For the first run, open `innovus` with no script and paste `innovus_pnr.tcl` one numbered section at a time. Looking at the layout after each step is how you learn what the step does.

1. Import: reads the Genus netlist, LEFs and the MMMC setup in `mmmc.tcl` (slow corner for setup, fast corner for hold).
2. Floorplan: square core at 40 % utilisation with a 10 µm margin. Instruction bus pins on the left edge, data bus pins on the right.
3. Power: core rings on the top two metals, vertical stripes every 40 µm, `sroute` for the standard-cell rails. `verifyConnectivity -type special` must be clean.
4. Placement with timing-driven mode, then `optDesign -preCTS`.
5. CTS with CCOpt, then setup and hold optimisation.
6. NanoRoute with timing and SI awareness and antenna fixing, then post-route optimisation in OCV mode.
7. Filler cells.
8. Checks: `verify_drc`, `verifyConnectivity`, `verifyProcessAntenna`, `timeDesign -postRoute` (setup and hold).
9. Outputs: routed netlist, LVS netlist with power pins, SPEF, SDF, DEF, LEF abstract and `outputs/rv32_core.gds`.

The likely first-run fixes are filler cell names, the layer names for rings/stripes and the GDS map file path. All of them live in `tech_setup.tcl`.

### 7.6 Signoff STA with Tempus

```bash
tempus -files tempus_sta.tcl -log logs/tempus
```

It reads the routed netlist and the SPEF Innovus extracted (`rcOut`). For a stricter signoff, extract with standalone Quantus QRC from the DEF instead and point `read_spef` at that file. Check `reports/tempus/summary.rpt` and `violators.rpt`.

### 7.7 DRC and LVS

These run on the GDS with the foundry rule decks from your PDK, using Pegasus (newer) or PVS:

1. Stream the GDS into Virtuoso: File → Import → Stream, with your PDK's tech library attached, or open the GDS in Pegasus DesignReview.
2. DRC: run Pegasus with the PDK's DRC runset on `outputs/rv32_core.gds`, top cell `rv32_core`.
3. LVS: compare the GDS against `outputs/rv32_core_lvs.v` (converted to a CDL/SPICE netlist with `v2lvs` or Virtuoso's netlist import, plus the standard-cell CDL from the PDK).

The exact runset names differ per kit, so check the kit's documentation folder. Innovus's `verify_drc` gives you a quick check against the LEF rules, but it does not replace the foundry DRC deck.

### 7.8 Gate-level simulation with SDF

```bash
xrun -64bit -access +rwc -timescale 1ns/1ps \
     <path>/gsclib045/verilog/slow_vdd1v0_basicCells.v \
     outputs/rv32_core_pnr.v  <wrapper + tb> \
     -sdf_cmd_file sdf.cmd
```

with `sdf.cmd` containing `COMPILED_SDF_FILE = "outputs/rv32_core_pnr.sdf", SCOPE = tb.dut;`. Use the post-route SDF so you see real delays.

---

## 8. Synopsys flow

Same idea, different tools. Source your Synopsys setup so `vcs`, `dc_shell`, `fm_shell`, `icc2_shell`, `pt_shell`, `StarXtract` and `icv` are on the path, then edit `asic/synopsys/tech_setup.tcl`. The defaults follow the SAED32nm educational kit (SAED32_EDK). If you have SAED14 or another kit, fill in the same variables.

### 8.1 RTL simulation with VCS

```bash
cd sim/build/add
vcs -full64 -sverilog +incdir+../../../rtl ../../../rtl/*.v ../../../sim/tb_soc.v -top tb_soc -debug_access+all
./simv
```

`verdi -ssf novas.fsdb` (after adding `$fsdbDumpvars` to the testbench) or `dve` for waveforms.

### 8.2 Synthesis with Design Compiler

```bash
cd asic/synopsys
dc_shell -f dc_syn.tcl | tee logs/dc.log
```

It runs `analyze`/`elaborate`/`link`, applies the SDC, runs `compile_ultra`, and writes the netlist, DDC, SDC, SDF and an SVF guidance file for Formality. Check `reports/qor.rpt` (worst slack, area, cell count) and `reports/violators.rpt` (should be empty).

### 8.3 Formality

```bash
fm_shell -f fm_lec.tcl | tee logs/fm.log
```

`verify` should report "Verification SUCCEEDED". The SVF file from DC is what lets Formality match registers that DC renamed or merged.

### 8.4 Place and route with IC Compiler II

```bash
icc2_shell -f icc2_pnr.tcl | tee logs/icc2.log
```

The script creates an NDM design library from the tech file and the reference cell library, sets up two scenarios (slow for setup, fast for hold), then:

- `initialize_floorplan` at 40 % utilisation, pins on the left and right edges
- PG ring on M7/M8, a vertical M8 mesh, M1 rails, `compile_pg`
- `place_opt`, `clock_opt`, `route_auto`, `route_opt`
- filler insertion, `check_routes`, `check_lvs`
- netlists, parasitics, DEF and `outputs/rv32_core.gds`

`save_block` after every step lets you reopen any stage with `open_block rv32_core.nlib:rv32_core_place` and `start_gui`.

The `set_operating_conditions` lines name the SAED32 library and corners directly. If you change kits, run `report_lib <libname>` to find the right names.

### 8.5 Extraction and PrimeTime

For signoff parasitics, run StarRC on the routed design with the PDK's `.nxtgrd` file (`NXTGRD_MAX` in `tech_setup.tcl`) and put the SPEF in `outputs/starrc/`. Without StarRC the script uses the parasitics ICC2 wrote.

```bash
pt_shell -f pt_sta.tcl | tee logs/pt.log
```

Check `reports/pt/global.rpt` for the WNS/TNS summary and `violators.rpt` for anything negative.

### 8.6 DRC and LVS with IC Validator

ICC2 can launch IC Validator directly once the runsets are set up:

```tcl
set_app_options -name signoff.check_drc.runset -value <PDK DRC runset>
signoff_check_drc
signoff_fix_drc        ;# optional automatic fixing
```

LVS is run with `icv` on the GDS against `outputs/rv32_core_lvs.v` and the standard-cell SPICE netlists from the PDK. The runset names come from your kit's documentation.

---

## 9. Where to take it next

Ideas in roughly increasing effort:

1. A UART transmitter at `0x2000_0020` so programs can `printf` to a terminal over the Nexys4's USB-UART.
2. Resolve JAL in ID to cut its penalty to one cycle; add a small branch target buffer.
3. The M extension (multiply/divide). A single-cycle multiplier maps onto DSP48 slices on the FPGA; divide is usually a 32-cycle iterative unit that stalls the pipeline.
4. Zicsr and machine-mode traps (`mtvec`, `mepc`, `mcause`, `mret`). That brings the `ma_data` test and interrupts within reach.
5. Instruction and data caches in front of the DDR2 memory on the Nexys4 DDR.
6. For the ASIC side: add SRAM macros (OpenRAM or DFFRAM for sky130) and harden `rv32_soc` with the core placed as a macro.

---

## Sources

- [riscv-tests](https://github.com/riscv-software-src/riscv-tests) (ISA test suite used for verification)
- [Digilent XDC files](https://github.com/Digilent/digilent-xdc) (Nexys-4-Master.xdc and Nexys-4-DDR-Master.xdc)
- [LibreLane Nix installation](https://librelane.readthedocs.io/en/latest/installation/nix_installation/installation_linux.html)
- [LibreLane newcomers' tutorial](https://librelane.readthedocs.io/en/latest/getting_started/newcomers/index.html)
- [LibreLane configuration reference](https://librelane.readthedocs.io/en/latest/reference/configuration.html)
