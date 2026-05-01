update_compile_order -fileset sources_1

# Launch implementation run:
launch_runs impl_1 -to_step write_bitstream -jobs 3

# Wait on implementation run:
wait_on_run -timeout 30 impl_1
