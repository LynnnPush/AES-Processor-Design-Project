#open simulation bd
open_bd_design {./vivado/riscy/riscy.srcs/sources_1/bd/riscv/riscv.bd}

#make sure to reload updated coe files to the memories:
set current_dir [pwd]
set coe_program_path [string cat $current_dir "/src/sw/mem_files/code.coe"]
set coe_data_path [string cat $current_dir "/src/sw/mem_files/data.coe"]
set_property -dict [list \
  CONFIG.Coe_File $coe_program_path \
  CONFIG.Load_Init_File {true} \
] [get_bd_cells instr_mem]
set_property -dict [list \
  CONFIG.Coe_File $coe_data_path \
  CONFIG.Load_Init_File {true} \
] [get_bd_cells data_mem]

#launch sim
launch_simulation

# Load waveform configuration file
open_wave_config ./src/simulation/zynq_tb_behav.wcfg

# Restart simulation to apply the waveform config properly
restart

# Run simulation until it finishes (e.g., until $finish or simulation time ends)
run -all
