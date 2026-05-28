//`include "riscv_core.sv"
`timescale 1ns / 1ps
module riscv_top_bram #(
    parameter BOOT_ADDR           = 32'h0080,
    parameter N_EXT_PERF_COUNTERS =  0,
    parameter INSTR_RDATA_WIDTH   = 32,
    parameter PULP_SECURE         =  0,
    parameter FPU                 =  0,
    parameter SHARED_FP           =  0,
    parameter SHARED_DSP_MULT     =  0,
    parameter SHARED_INT_DIV      =  0,
    parameter SHARED_FP_DIVSQRT   =  0,
    parameter WAPUTYPE            =  0,
    parameter APU_NARGS_CPU       =  3,
    parameter APU_WOP_CPU         =  6,
    parameter APU_NDSFLAGS_CPU    = 15,
    parameter APU_NUSFLAGS_CPU    =  5
 )
(
    input  wire      clk,
    input  wire      rstn,
    input  wire      REBOOT,
    
    // BRAM MASTER PORT - INSTR        
    output wire [31:0]   instr_addr,
    output wire [ 3:0]   instr_wen,
    input  wire [31:0]   instr_rdata,
    output wire [31:0]   instr_wdata,

    // BRAM MASTER PORT - DATA        
    output wire [31:0]   dat_addr,
    output wire [ 3:0]   dat_wen,
    input  wire [31:0]   dat_rdata,
    output wire [31:0]   dat_wdata,
    
    //Interrupts
    input  wire [31:0]       irqs,                 // level sensitive IR lines

    // Debug Interface
    input  wire        debug_req_i,
    output wire        debug_gnt_o,
    output wire        debug_rvalid_o,
    input  wire [14:0] debug_addr_i,
    input  wire        debug_we_i,
    input  wire [31:0] debug_wdata_i,
    output wire [31:0] debug_rdata_o,
    output wire        debug_halted_o,
    input  wire        debug_halt_i,
    input  wire        debug_resume_i,

    // CPU Control Signals
    input  wire        fetch_enable_i,
    output wire        core_sleep_o
);

    wire          core_instr_req;
    wire          core_instr_gnt;
    wire          core_instr_rvalid;
    wire [31:0]    core_instr_addr;
    wire [31:0]    core_instr_rdata;
     
    wire          core_lsu_req;
    wire          core_lsu_gnt;
    wire          core_lsu_rvalid;
    wire [31:0]    core_lsu_addr;
    wire          core_lsu_we;
    wire [3:0]    core_lsu_be;
    wire [31:0]    core_lsu_rdata;
    wire [31:0]    core_lsu_wdata;
    

    cv32e40p_core #(
    ) riscv_core (
        // Clock and Reset
        .clk_i           ( clk            ),
        .rst_ni          ( rstn           ),
    
        .pulp_clock_en_i( 1'b1          ), // PULP clock enable (only used if PULP_CLUSTER = 1)
        .scan_cg_en_i   ( 1'b0         ),  // Enable all clock gates for testing
    
        // Core ID, Cluster ID, debug mode halt address and boot address are considered more or less static
        .boot_addr_i         ( BOOT_ADDR        ),
        .mtvec_addr_i        (                  ),
        .dm_halt_addr_i      (                  ),
        .hart_id_i           (                  ),
        .dm_exception_addr_i (                  ),
    
        // Instruction memory interface
        .instr_addr_o    ( core_instr_addr   ),
        .instr_req_o     ( core_instr_req    ),
        .instr_rdata_i   ( core_instr_rdata  ),
        .instr_gnt_i     ( core_instr_gnt    ),
        .instr_rvalid_i  ( core_instr_rvalid ),
    
        // Data memory interface
        .data_addr_o     ( core_lsu_addr     ),
        .data_wdata_o    ( core_lsu_wdata    ),
        .data_we_o       ( core_lsu_we       ),
        .data_req_o      ( core_lsu_req      ),
        .data_be_o       ( core_lsu_be       ),
        .data_rdata_i    ( core_lsu_rdata    ),
        .data_gnt_i      ( core_lsu_gnt      ),
        .data_rvalid_i   ( core_lsu_rvalid   ),
    
        // apu-interconnect
        // handshake signals
        .apu_req_o       (             ),
        .apu_gnt_i       ( 1'b1        ),
        // request channel
        .apu_operands_o  (             ),
        .apu_op_o        (             ),
        .apu_flags_o     (             ),
        // response channel
        .apu_rvalid_i    ( 1'b0        ),
        .apu_result_i    ( 32'd0       ),
        .apu_flags_i     ( 5'd0        ),
    
        // Interrupt inputs
        .irq_i           ( (|irqs)           ), // CLINT interrupts + CLINT extension interrupts
        .irq_ack_o       (                   ),
        .irq_id_o        (                   ),
    
        // Debug Interface
        .debug_req_i        ( 1'b0              ),
        .debug_havereset_o  (                   ),
        .debug_running_o    (                   ),
        .debug_halted_o     (                   ),
    
        // CPU Control Signals
        .fetch_enable_i  ( fetch_enable_i    ),
        .core_sleep_o    ( core_sleep_o      )
    );
 


    core_2_bram #(
        .R_LATENCY_IN_CYCLES(1)
    )instr_bram_if(
        .clk_i(clk),
        .rst_ni(rstn),
        .req_i(core_instr_req),
        .gnt_o(core_instr_gnt),
        .rvalid_o(core_instr_rvalid),
        .addr_i(core_instr_addr),
        .we_i(1'b0),
        .be_i(4'b1111),
        .rdata_o(core_instr_rdata),
        .wdata_i(32'h0),
    
        .addr(instr_addr),
        .dout(instr_wdata),
        .din(instr_rdata),
        .weout()
    );
    assign instr_wen = 4'b0000; //never write to instr bram

    core_2_bram #(
        .R_LATENCY_IN_CYCLES(1)
    )data_bram_if(
        .clk_i(clk),
        .rst_ni(rstn),
        .req_i(core_lsu_req),
        .gnt_o(core_lsu_gnt),
        .rvalid_o(core_lsu_rvalid),
        .addr_i(core_lsu_addr),
        .we_i(core_lsu_we),
        .be_i(core_lsu_be),
        .rdata_o(core_lsu_rdata),
        .wdata_i(core_lsu_wdata),

        .addr(dat_addr),
        .dout(dat_wdata),
        .din(dat_rdata),
        .weout(dat_wen)
    );

endmodule
