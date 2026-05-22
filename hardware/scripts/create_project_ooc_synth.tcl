# create ooc synthesis project
create_project ooc_riscy ./vivado/ooc_riscy -part xc7z020clg400-1 -force

# Optionally, add directories
add_files -norecurse ./src/design/riscy/
add_files -norecurse ./src/design/riscy/include/

update_compile_order -fileset sources_1

set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -mode_out_of_context -objects [get_runs synth_1]

# Set the default top-level module for the project
set_property top riscv_ooc_top_level_wrapper [current_fileset]
# set properties of the ooc top level wrapper: used in out of context synthesis
set_property USED_IN {synthesis implementation out_of_context} [get_files -all riscv_ooc_top_level_wrapper.sv]


# Add XDC constraints
# add_files ./src/design/constraints/ooc_constraints.xdc
add_files -fileset constrs_1 -norecurse ./src/design/constraints/ooc_constraints.xdc

# Run out-of-order synthesis
synth_design -top riscv_ooc_top_level_wrapper -constrset constrs_1 -part xc7z010clg400-1 -mode out_of_context

# Write synthesized design
write_checkpoint -force ./vivado/ooc_riscy/ooc_riscy.runs/ooc_synth/riscv_synth.dcp

# Report timing
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets -name timing_1 -file ./vivado/ooc_riscy/ooc_riscy.runs/ooc_synth/ooc_timing_summary.txt

# Report Utilization
report_utilization -name utilization_1

set core_cell [lindex [get_cells -hierarchical -filter {NAME =~ *riscv_core*}] 0]
if {$core_cell eq ""} {
    puts "WARNING: Could not find riscv_core cell, skipping per-cell utilization report"
} else {
    puts "Reporting utilization for cell: $core_cell"
    report_utilization -cells [get_cells $core_cell] \
        -file ./vivado/ooc_riscy/ooc_riscy.runs/ooc_synth/ooc_utilization_summary.txt
}