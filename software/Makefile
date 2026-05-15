# Define folders
SOFT_DIR := soft
ACC_DIR := acc
INCLUDE_DIR := include
OUTPUT_DIR := output
BIN_DIR   := bin_files
SIM_MEM_DIR  := ../hardware/src/sw/mem_files
FPGA_MEM_DIR := ../hardware/src/sw/fpga/riscy/mem_files
# Default configuration
CONFIG = rv32-standard

PYTHON = python3
include config/$(CONFIG).conf

# Compiler flags
LLVM_CFLAGS += --target=riscv32 -Wall
LLVM_CFLAGS += -I./share
LLVM_CFLAGS += -I./$(SOFT_DIR)
LLVM_CFLAGS += -I./$(ACC_DIR)
LLVM_CFLAGS += -I./$(INCLUDE_DIR)
LLVM_CFLAGS += $(CONF_CFLAGS)
LLVM_CFLAGS += -msmall-data-limit=8  -std=gnu11 -nostartfiles -ffunction-sections -fdata-sections -g3 -o0
LLVM_CFLAGS += --sysroot=$(RISCV_GCC)/$(RISCV_ARCH)


GCC_WARNS  = -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings

# Define common files
MAIN_SRC := main.c 
MAIN_ASM := crt0.riscv.S
# Define source files
SOFT_SRC := $(wildcard $(SOFT_DIR)/*.c)
ACC_SRC := $(wildcard $(ACC_DIR)/*.S)
INCLUDE_SRC := $(wildcard $(INCLUDE_DIR)/*.c)

PYTHON_FLAGS_CODE = -b 0x8000 -s 0x8000 -f
PYTHON_FLAGS_DATA = -b 0x100000 -s 0x8000 -f

# Define object files
SOFT_OBJS := $(patsubst %.c,%.o,$(SOFT_SRC)) $(patsubst %.c,%.o,$(INCLUDE_SRC)) $(patsubst %.c,%.o,$(MAIN_SRC))
ACC_OBJS  := $(patsubst %.S,%.o,$(ACC_SRC)) $(patsubst %.c,%.o,$(INCLUDE_SRC)) $(patsubst %.c,%.o,$(MAIN_SRC)) 
SREC_OBJS := $(OUTPUT_DIR)/soft.srec $(OUTPUT_DIR)/acc.srec
ELF_OBJS := $(OUTPUT_DIR)/soft.elf $(OUTPUT_DIR)/acc.elf

LINKER_SCRIPT := link.common.ld
LLVM_LDFLAGS := -Wl,--build-id=none -Wl,-Map=aes.map -T $(LINKER_SCRIPT) -lc -nostdlib

# Create output directory
$(shell mkdir -p $(OUTPUT_DIR))

# Compilation rules
.PHONY: all soft clean

all: soft 

# Compile crt0 startup file
crt0.riscv.o: crt0.riscv.S
	$(LLVMCC) $(LLVM_CFLAGS) -c -x assembler-with-cpp -o $@ $<

# Compile object files
%.o: %.c
	$(LLVMCC) $(LLVM_CFLAGS) -c -o $@ $<

soft: $(SOFT_OBJS) crt0.riscv.o
	$(LLVMCC) $(LLVM_CFLAGS) $(LLVM_LDFLAGS) -msmall-data-limit=8 -o $(OUTPUT_DIR)/soft.elf  $(SOFT_OBJS) crt0.riscv.o
	$(OBJCOPY) -O srec $(OUTPUT_DIR)/soft.elf $(OUTPUT_DIR)/soft.srec
	$(PYTHON) python_script/srec_to_coe.py   $(OUTPUT_DIR)/soft.srec $(PYTHON_FLAGS_CODE) -o $(BIN_DIR)/code.coe
	$(PYTHON) python_script/srec_to_coe.py   $(OUTPUT_DIR)/soft.srec $(PYTHON_FLAGS_DATA) -o $(BIN_DIR)/data.coe
	@mkdir -p $(SIM_MEM_DIR) $(FPGA_MEM_DIR)
	cp $(BIN_DIR)/code.coe $(BIN_DIR)/data.coe $(SIM_MEM_DIR)/
	cp $(BIN_DIR)/code.coe $(BIN_DIR)/data.coe $(FPGA_MEM_DIR)/

# Clean rule
clean:
	rm -f -r crt0.riscv.o aes.map $(SOFT_OBJS) $(ACC_OBJS) $(OUTPUT_DIR)

