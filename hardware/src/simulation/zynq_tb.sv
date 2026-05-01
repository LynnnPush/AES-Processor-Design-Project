/* # ########################################################################
# Copyright (C) 2019, Xilinx Inc - All rights reserved

# Licensed under the Apache License, Version 2.0 (the "License"). You may
# not use this file except in compliance with the License. A copy of the
# License is located at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
# ######################################################################## */

`timescale 1ns / 1ps

module zynq_tb;

    reg [31:0] base_addr  = 32'h4000_0000;
    reg [31:0] off_set    = 32'h0000_4320;
    reg [31:0] addr = 32'h4000_0000;
    reg [31:0] base_addr_data       = 32'h4200_0000;
    reg [31:0] base_addr_reboot     = 32'h4000_8000;
    reg [31:0] base_addr_reg_bank   = 32'h4000_9000;
    reg [31:0] expected_result_addr = base_addr_data + 32'h2030;
    reg [31:0] result_addr          = base_addr_data + 32'h2040;
    //reg [31:0] end_test_mem_snoop_addr = 32'h4000_9000;
    reg tb_ACLK;
    reg tb_ARESETn;
   
    wire temp_clk;
    wire temp_rstn;
    wire sys_clk;
    wire sys_rstn; 
   
    reg [31:0] expected_datas [0:3] = '{32'h1409A5FB, 32'h1FF44B71, 32'hBEAA252E, 32'h0F08F9AA};
    reg [31:0] read_data[0:3];
    reg [31:0] end_read_data;
    reg [31:0] write_data;
    //wire [3:0] leds;
    reg resp; 
    
    //------------------------------------------------------------------------
    // Address map:
    //------------------------------------------------------------------------   

    // 0x4000_0000 - 0x4000_7FFF: Instruction memory
    // 0x4200_0000 - 0x4200_7FFF: Data memory
    // - 0x4200_2000: [31:0]: End sequence
    // - 0x4200_2004: [31:0]: Ciphertext matches expected
    // - 0x4200_2030: [31:0]: Expected ciphertext [0]
    // - 0x4200_2034: [31:0]: Expected ciphertext [1]
    // - 0x4200_2038: [31:0]: Expected ciphertext [2]
    // - 0x4200_203C: [31:0]: Expected ciphertext [3]
    // - 0x4200_2040: [31:0]: Calculated ciphertext [0]
    // - 0x4200_2044: [31:0]: Calculated ciphertext [1]
    // - 0x4200_2048: [31:0]: Calculated ciphertext [2]
    // - 0x4200_204C: [31:0]: Calculated ciphertext [3]
    // 0x4000_8000  - 0x4000_8FFF: Reboot riscv
    // - 0x4000_8010: [0]: Reboot riscv
    // - 0x4000_8010: [4]: Fetch enable riscv
    // 0x4000_9000  - 0x4000_9FFF: Register bank
    // - 0x4000_9000: [0]: End sequence detected
    // - 0x4000_9004: [31:0]: Number of clk cycles from fetch enable to end sequence detected
    
    initial 
    begin       
        tb_ACLK = 1'b0;
    end
    
    //------------------------------------------------------------------------
    // Simple Clock Generator
    //------------------------------------------------------------------------
    
    always #10 tb_ACLK = !tb_ACLK;


    //------------------------------------------------------------------------
    // Main body of the testbench
    //------------------------------------------------------------------------   
    initial
    begin
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.set_debug_level_info(0);

        $display ("running the zynq_tb");
        tb_ARESETn = 1'b0;
        repeat(20)@(posedge tb_ACLK);        
        tb_ARESETn = 1'b1;
        @(posedge tb_ACLK);
        
        repeat(5) @(posedge tb_ACLK);
          
        //Reset the PL
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.fpga_soft_reset(32'h1);
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.fpga_soft_reset(32'h0);
		#2000
		#200
        
        main_core_execution();

        $display ("Simulation completed");
        $stop;
    end

    assign temp_clk = tb_ACLK;
    assign temp_rstn = tb_ARESETn;
    assign sys_clk = zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.FCLK_CLK0;
    assign sys_rstn = zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.FCLK_RESET0_N;
   
    //------------------------------------------------------------------------
    // CPI stack pipeline tracer
    //------------------------------------------------------------------------
    // Logs per-cycle pipeline state to a CSV during the active fetch window.
    // Post-processed by software/python_script/cpi_stack.py to produce a CPI
    // stack breakdown (useful exec / data hazard / mem stall / branch / etc.).
    integer trace_file = 0;
    integer cycle_count = 0;
    wire    fetch_en_w = zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.fetch_enable_i;

    initial begin
        trace_file = $fopen("../../../../../../src/simulation/pipeline_trace.csv", "w");
        $fwrite(trace_file,
            "cycle,pc_if,pc_id,instr,is_decoding,id_ready,ex_ready,load_stall,jr_stall,misaligned_stall,branch_dec,pc_set,data_req,data_gnt,data_rvalid,if_busy,perf_imiss,instr_valid_id\n");
    end

    always @(posedge sys_clk) begin
        if (sys_rstn && fetch_en_w) begin
            cycle_count <= cycle_count + 1;
            $fwrite(trace_file, "%0d,0x%08h,0x%08h,0x%08h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                cycle_count,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.pc_if,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.pc_id,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.instr_rdata_id,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.is_decoding,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.id_stage_i.id_ready_o,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.id_stage_i.ex_ready_i,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.id_stage_i.load_stall,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.id_stage_i.jr_stall,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.id_stage_i.misaligned_stall,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.branch_decision,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.pc_set,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.data_req_o,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.data_gnt_i,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.data_rvalid_i,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.if_busy,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.perf_imiss,
                zynq_tb.zynq_sys.riscv_i.riscv_top_bram_0.inst.riscv_core.instr_valid_id
            );
        end
    end

    final begin
        if (trace_file != 0) $fclose(trace_file);
    end

    riscv_wrapper zynq_sys(
        .DDR_addr(),
        .DDR_ba(),
        .DDR_cas_n(),
        .DDR_ck_n(),
        .DDR_ck_p(),
        //.DDR_cke(),
        .DDR_cs_n(),
        .DDR_dm(),
        .DDR_dq(),
        .DDR_dqs_n(),
        .DDR_dqs_p(),
        .DDR_odt(),
        .DDR_ras_n(),
        .DDR_reset_n(),
        .DDR_we_n(),
        .FIXED_IO_ddr_vrn(),
        .FIXED_IO_ddr_vrp(),
        .FIXED_IO_mio(),
        .FIXED_IO_ps_clk(temp_clk),
        .FIXED_IO_ps_porb(temp_rstn ),
        .FIXED_IO_ps_srstb(temp_rstn)
        //.ext_reset(tb_ARESETn)
    );
    
endmodule

task main_core_execution();

    $display("Setting fetch_enable pin of the riscv to 1...");
    zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.write_data((zynq_tb.base_addr_reboot + 8'h10), 4, 32'h0000_0010, zynq_tb.resp);
    repeat(5) @(posedge zynq_tb.sys_clk);
    
    // We check the register connected to the mem_snoop until it detects the end sequence being written to memory (0x102000 = 0xDEADBEEF)
    repeat (8000) begin
//       scan_file = $fscanf(data_file, "%d\n", capture_data);
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.base_addr_reg_bank,4,zynq_tb.end_read_data,zynq_tb.resp);
	    if(zynq_tb.end_read_data[0] == 1'b1) begin
            break;
        end
        #400;
    end
    
    $display("Setting fetch_enable pin of the riscv to 0...");
    zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.write_data((zynq_tb.base_addr_reboot + 8'h10), 4, 32'h0000_0000, zynq_tb.resp);
    repeat(5) @(posedge zynq_tb.sys_clk);

    // Lets double check that the end sequence was written to the right address and how many clk cycles it took to get there
    if(zynq_tb.end_read_data[0] == 1'b0) begin
        $error ("End sequence 0xDEADBEEF was not found in memory");
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.base_addr_data + 32'h2000,4,zynq_tb.end_read_data,zynq_tb.resp);
        $display ("End sequence 0xDEADBEEF was not found in a single write to memory, but found %0h later", zynq_tb.end_read_data);
    end else begin
        // check how many clk cycles it took:
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.base_addr_reg_bank+32'h04,4,zynq_tb.end_read_data,zynq_tb.resp);
        // display how many clk cycles
        $display ("Test completed in %0d clk cycles", zynq_tb.end_read_data);
    end

    // Lets read expected ciphertext
    for (int i=0; i<4; i++) begin
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.expected_result_addr + (32'h4*i),4,zynq_tb.expected_datas[i],zynq_tb.resp);
        $display("Expected ciphertext (%0h): %0h", zynq_tb.expected_result_addr + (32'h4*i), zynq_tb.expected_datas[i]);
    end

    // Lets read calculated ciphertext
    for (int i=0; i<4; i++) begin
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.result_addr + (32'h4*i),4,zynq_tb.read_data[i],zynq_tb.resp);
        $display("Calculated ciphertext (%0h): %0h", zynq_tb.result_addr + (32'h4*i), zynq_tb.read_data[i]);
    end

    if(zynq_tb.read_data == zynq_tb.expected_datas) begin
       $display ("Test PASSED");
    end else begin
       $error ("Test FAILED");
    end
    #400;

endtask

task test_read_data_memory();
    // https://adaptivesupport.amd.com/s/question/0D54U00007BExvhSAD/can-i-access-the-saxilpd-of-the-zynq-ultrascale-using-the-command-writedata-and-readdata-of-zynq-ultrascale-vip-apis?language=en_US
    // zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.write_data(in [31:0]addr, in [7:0]wr_size, in [1023:0]wr_data, out response);
    // vip info: https://docs.amd.com/v/u/en-US/ds940-zynq-vip
    // Read addresses from data memory:
    zynq_tb.addr=zynq_tb.base_addr_data;
    @(posedge zynq_tb.sys_clk);
    for (int i = 0; i < 5; i++) begin
        zynq_tb.zynq_sys.riscv_i.processing_system7_0.inst.read_data(zynq_tb.addr,4,zynq_tb.read_data[0],zynq_tb.resp);
        $display("Read data (%0h): %0h", zynq_tb.addr, zynq_tb.read_data[0]);
        zynq_tb.addr += 32'h4;
        repeat(5) @(posedge zynq_tb.sys_clk);
    end

endtask

