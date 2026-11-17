# Build the board demo into imem.hex / dmem.hex
#   make            -> build
#   make install    -> copy the hex files next to the Vivado sources (fpga/nexys4)
#   make dump       -> disassembly
CROSS ?= riscv64-unknown-elf-
CC     = $(CROSS)gcc
OBJCOPY= $(CROSS)objcopy
OBJDUMP= $(CROSS)objdump

CFLAGS = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles \
         -fno-builtin -Wall -T ../link.ld $(CFLAGS_EXTRA)

all: imem.hex dmem.hex

demo.elf: crt0.S demo.c ../link.ld
	$(CC) $(CFLAGS) -o $@ crt0.S demo.c

imem.hex: demo.elf
	$(OBJCOPY) -O binary -j .text $< imem.bin
	python3 ../elf2hex.py imem.bin $@

dmem.hex: demo.elf
	$(OBJCOPY) -O binary -j .data $< dmem.bin
	python3 ../elf2hex.py dmem.bin $@

dump: demo.elf
	$(OBJDUMP) -d $< | less

install: imem.hex dmem.hex
	cp imem.hex dmem.hex ../../fpga/nexys4/

clean:
	rm -f *.elf *.bin *.hex
