// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Matthias Baer - baermatt@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                 Michael Gautschi - gautschi@iis.ee.ethz.ch                 //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                 Halfdan Bechmann - halfdan.bechmann@silabs.com             //
//                 Øystein Knauserud - oystein.knauserud@silabs.com           //
//                 Michael Platzer - michael.platzer@tuwien.ac.at             //
//                                                                            //
// Design Name:    Top level module                                           //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Top level module of the RISC-V core.                       //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module riscv_ooc_top_level_wrapper #()
(
    // Clock and Reset
    input logic clk_i,
    input logic rst_ni,

    input logic pulp_clock_en_i,  // PULP clock enable (only used if PULP_CLUSTER = 1)
    input logic scan_cg_en_i,  // Enable all clock gates for testing

    // Core ID, Cluster ID, debug mode halt address and boot address are considered more or less static
    input logic [31:0] boot_addr_i,
    input logic [31:0] mtvec_addr_i,
    input logic [31:0] dm_halt_addr_i,
    input logic [31:0] hart_id_i,
    input logic [31:0] dm_exception_addr_i,

    // Instruction memory interface
    output logic        instr_req_o,
    input  logic        instr_gnt_i,
    input  logic        instr_rvalid_i,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,

    // Data memory interface
    output logic        data_req_o,
    input  logic        data_gnt_i,
    input  logic        data_rvalid_i,
    output logic        data_we_o,
    output logic [ 3:0] data_be_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,

    // apu-interconnect
    // handshake signals
    output logic             apu_req_o,
    input  logic             apu_gnt_i,
    // request channel
    output logic [2:0][31:0] apu_operands_o,
    output logic [5:0]       apu_op_o,
    output logic [14:0]      apu_flags_o,
    // response channel
    input  logic             apu_rvalid_i,
    input  logic [31:0]      apu_result_i,
    input  logic [4:0]       apu_flags_i,

    // Interrupt inputs
    input  logic [31:0] irq_i,  // CLINT interrupts + CLINT extension interrupts
    output logic        irq_ack_o,
    output logic [ 4:0] irq_id_o,

    // Debug Interface
    input  logic debug_req_i,
    output logic debug_havereset_o,
    output logic debug_running_o,
    output logic debug_halted_o,

    // CPU Control Signals
    input  logic fetch_enable_i,
    output logic core_sleep_o
);

    // Flip-flop signals
    logic pulp_clock_en_i_ff;
    logic scan_cg_en_i_ff;
    logic [31:0] boot_addr_i_ff;
    logic [31:0] mtvec_addr_i_ff;
    logic [31:0] dm_halt_addr_i_ff;
    logic [31:0] hart_id_i_ff;
    logic [31:0] dm_exception_addr_i_ff;
    logic instr_gnt_i_ff;
    logic instr_rvalid_i_ff;
    logic [31:0] instr_rdata_i_ff;
    logic data_gnt_i_ff;
    logic data_rvalid_i_ff;
    logic [31:0] data_rdata_i_ff;
    logic [31:0] apu_result_i_ff;
    logic apu_gnt_i_ff;
    logic apu_rvalid_i_ff;
    logic [4:0] apu_flags_i_ff;
    logic [31:0] irq_i_ff;
    logic debug_req_i_ff;
    logic fetch_enable_i_ff;

    logic instr_req_o_ff;
    logic [31:0] instr_addr_o_ff;
    logic data_req_o_ff;
    logic data_we_o_ff;
    logic [3:0] data_be_o_ff;
    logic [31:0] data_addr_o_ff;
    logic [31:0] data_wdata_o_ff;
    logic apu_req_o_ff;
    logic [2:0][31:0] apu_operands_o_ff;
    logic [5:0] apu_op_o_ff;
    logic [14:0] apu_flags_o_ff;
    logic irq_ack_o_ff;
    logic [4:0] irq_id_o_ff;
    logic debug_havereset_o_ff;
    logic debug_running_o_ff;
    logic debug_halted_o_ff;
    logic core_sleep_o_ff;

    always_ff @(posedge clk_i) begin
        pulp_clock_en_i_ff    <= pulp_clock_en_i;
        scan_cg_en_i_ff       <= scan_cg_en_i;
        boot_addr_i_ff        <= boot_addr_i;
        mtvec_addr_i_ff       <= mtvec_addr_i;
        dm_halt_addr_i_ff     <= dm_halt_addr_i;
        hart_id_i_ff          <= hart_id_i;
        dm_exception_addr_i_ff<= dm_exception_addr_i;
        instr_gnt_i_ff        <= instr_gnt_i;
        instr_rvalid_i_ff     <= instr_rvalid_i;
        instr_rdata_i_ff      <= instr_rdata_i;
        data_gnt_i_ff         <= data_gnt_i;
        data_rvalid_i_ff      <= data_rvalid_i;
        data_rdata_i_ff       <= data_rdata_i;
        apu_result_i_ff       <= apu_result_i;
        apu_gnt_i_ff          <= apu_gnt_i;
        apu_rvalid_i_ff       <= apu_rvalid_i;
        apu_flags_i_ff        <= apu_flags_i;
        irq_i_ff              <= irq_i;
        debug_req_i_ff        <= debug_req_i;
        fetch_enable_i_ff     <= fetch_enable_i;
        instr_req_o           <= instr_req_o_ff;
        instr_addr_o          <= instr_addr_o_ff;
        data_req_o            <= data_req_o_ff;
        data_we_o             <= data_we_o_ff;
        data_be_o             <= data_be_o_ff;
        data_addr_o           <= data_addr_o_ff;
        data_wdata_o          <= data_wdata_o_ff;
        apu_req_o             <= apu_req_o_ff;
        apu_operands_o        <= apu_operands_o_ff;
        apu_op_o              <= apu_op_o_ff;
        apu_flags_o           <= apu_flags_o_ff;
        irq_ack_o             <= irq_ack_o_ff;
        irq_id_o              <= irq_id_o_ff;
        debug_havereset_o     <= debug_havereset_o_ff;
        debug_running_o       <= debug_running_o_ff;
        debug_halted_o        <= debug_halted_o_ff;
        core_sleep_o          <= core_sleep_o_ff;
    end

    // Instantiate the core module
    cv32e40p_core #(
    ) riscv_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
    
        .pulp_clock_en_i(pulp_clock_en_i_ff),  // PULP clock enable (only used if PULP_CLUSTER = 1)
        .scan_cg_en_i(scan_cg_en_i_ff),  // Enable all clock gates for testing
    
        // Core ID, Cluster ID, debug mode halt address and boot address are considered more or less static
        .boot_addr_i(boot_addr_i_ff),
        .mtvec_addr_i(mtvec_addr_i_ff),
        .dm_halt_addr_i(dm_halt_addr_i_ff),
        .hart_id_i(hart_id_i_ff),
        .dm_exception_addr_i(dm_exception_addr_i_ff),
    
        // Instruction memory interface
        .instr_req_o(instr_req_o_ff),
        .instr_gnt_i(instr_gnt_i_ff),
        .instr_rvalid_i(instr_rvalid_i_ff),
        .instr_addr_o(instr_addr_o_ff),
        .instr_rdata_i(instr_rdata_i_ff),
    
        // Data memory interface
        .data_req_o(data_req_o_ff),
        .data_gnt_i(data_gnt_i_ff),
        .data_rvalid_i(data_rvalid_i_ff),
        .data_we_o(data_we_o_ff),
        .data_be_o(data_be_o_ff),
        .data_addr_o(data_addr_o_ff),
        .data_wdata_o(data_wdata_o_ff),
        .data_rdata_i(data_rdata_i_ff),
    
        // apu-interconnect
        // handshake signals
        .apu_req_o(apu_req_o_ff),
        .apu_gnt_i(apu_gnt_i_ff),
        // request channel
        .apu_operands_o(apu_operands_o_ff),
        .apu_op_o(apu_op_o_ff),
        .apu_flags_o(apu_flags_o_ff),
        // response channel
        .apu_rvalid_i(apu_rvalid_i_ff),
        .apu_result_i(apu_result_i_ff),
        .apu_flags_i(apu_flags_i_ff),
    
        // Interrupt inputs
        .irq_i(irq_i_ff),  // CLINT interrupts + CLINT extension interrupts
        .irq_ack_o(irq_ack_o_ff),
        .irq_id_o(irq_id_o_ff),
    
        // Debug Interface
        .debug_req_i(debug_req_i_ff),
        .debug_havereset_o(debug_havereset_o_ff),
        .debug_running_o(debug_running_o_ff),
        .debug_halted_o(debug_halted_o_ff),
    
        // CPU Control Signals
        .fetch_enable_i(fetch_enable_i_ff),
        .core_sleep_o(core_sleep_o_ff)
 );
endmodule
