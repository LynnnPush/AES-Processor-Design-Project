// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51.

////////////////////////////////////////////////////////////////////////////////
// Design Name:    AES32 scalar-crypto unit                                   //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Combinational implementation of the RISC-V scalar          //
//                 cryptography extension instruction aes32esmi (Zkne).       //
//                                                                            //
//                 rd = rs1 ^ rot_left( MixColumn_fwd( SBox( rs2[bs] ) ),     //
//                                       bs * 8 )                             //
//                                                                            //
//                 - SBox     : standard AES forward S-box                    //
//                 - MixCol   : forward MixColumn applied to the column       //
//                              {s, s, s, s} -> {2*s, 1*s, 1*s, 3*s} in GF(2^8)//
//                              i.e. the four-byte word  [2s, s, s, 3s]       //
////////////////////////////////////////////////////////////////////////////////

module cv32e40p_aes
(
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    input  logic [ 1:0] bs_i,         // byte-select from instr[31:30]
    output logic [31:0] result_o
);

    // ------------------------------------------------------------------------
    // Byte-select: pick byte bs of rs2
    // ------------------------------------------------------------------------
    logic [7:0] sb_in;
    always_comb begin
        unique case (bs_i)
            2'd0: sb_in = rs2_i[ 7: 0];
            2'd1: sb_in = rs2_i[15: 8];
            2'd2: sb_in = rs2_i[23:16];
            2'd3: sb_in = rs2_i[31:24];
        endcase
    end

    // ------------------------------------------------------------------------
    // AES forward S-box (256x8 LUT - synthesizes to LUTs on the FPGA)
    // ------------------------------------------------------------------------
    logic [7:0] sb_out;
    always_comb begin
        unique case (sb_in)
            8'h00: sb_out = 8'h63; 8'h01: sb_out = 8'h7c; 8'h02: sb_out = 8'h77; 8'h03: sb_out = 8'h7b;
            8'h04: sb_out = 8'hf2; 8'h05: sb_out = 8'h6b; 8'h06: sb_out = 8'h6f; 8'h07: sb_out = 8'hc5;
            8'h08: sb_out = 8'h30; 8'h09: sb_out = 8'h01; 8'h0a: sb_out = 8'h67; 8'h0b: sb_out = 8'h2b;
            8'h0c: sb_out = 8'hfe; 8'h0d: sb_out = 8'hd7; 8'h0e: sb_out = 8'hab; 8'h0f: sb_out = 8'h76;
            8'h10: sb_out = 8'hca; 8'h11: sb_out = 8'h82; 8'h12: sb_out = 8'hc9; 8'h13: sb_out = 8'h7d;
            8'h14: sb_out = 8'hfa; 8'h15: sb_out = 8'h59; 8'h16: sb_out = 8'h47; 8'h17: sb_out = 8'hf0;
            8'h18: sb_out = 8'had; 8'h19: sb_out = 8'hd4; 8'h1a: sb_out = 8'ha2; 8'h1b: sb_out = 8'haf;
            8'h1c: sb_out = 8'h9c; 8'h1d: sb_out = 8'ha4; 8'h1e: sb_out = 8'h72; 8'h1f: sb_out = 8'hc0;
            8'h20: sb_out = 8'hb7; 8'h21: sb_out = 8'hfd; 8'h22: sb_out = 8'h93; 8'h23: sb_out = 8'h26;
            8'h24: sb_out = 8'h36; 8'h25: sb_out = 8'h3f; 8'h26: sb_out = 8'hf7; 8'h27: sb_out = 8'hcc;
            8'h28: sb_out = 8'h34; 8'h29: sb_out = 8'ha5; 8'h2a: sb_out = 8'he5; 8'h2b: sb_out = 8'hf1;
            8'h2c: sb_out = 8'h71; 8'h2d: sb_out = 8'hd8; 8'h2e: sb_out = 8'h31; 8'h2f: sb_out = 8'h15;
            8'h30: sb_out = 8'h04; 8'h31: sb_out = 8'hc7; 8'h32: sb_out = 8'h23; 8'h33: sb_out = 8'hc3;
            8'h34: sb_out = 8'h18; 8'h35: sb_out = 8'h96; 8'h36: sb_out = 8'h05; 8'h37: sb_out = 8'h9a;
            8'h38: sb_out = 8'h07; 8'h39: sb_out = 8'h12; 8'h3a: sb_out = 8'h80; 8'h3b: sb_out = 8'he2;
            8'h3c: sb_out = 8'heb; 8'h3d: sb_out = 8'h27; 8'h3e: sb_out = 8'hb2; 8'h3f: sb_out = 8'h75;
            8'h40: sb_out = 8'h09; 8'h41: sb_out = 8'h83; 8'h42: sb_out = 8'h2c; 8'h43: sb_out = 8'h1a;
            8'h44: sb_out = 8'h1b; 8'h45: sb_out = 8'h6e; 8'h46: sb_out = 8'h5a; 8'h47: sb_out = 8'ha0;
            8'h48: sb_out = 8'h52; 8'h49: sb_out = 8'h3b; 8'h4a: sb_out = 8'hd6; 8'h4b: sb_out = 8'hb3;
            8'h4c: sb_out = 8'h29; 8'h4d: sb_out = 8'he3; 8'h4e: sb_out = 8'h2f; 8'h4f: sb_out = 8'h84;
            8'h50: sb_out = 8'h53; 8'h51: sb_out = 8'hd1; 8'h52: sb_out = 8'h00; 8'h53: sb_out = 8'hed;
            8'h54: sb_out = 8'h20; 8'h55: sb_out = 8'hfc; 8'h56: sb_out = 8'hb1; 8'h57: sb_out = 8'h5b;
            8'h58: sb_out = 8'h6a; 8'h59: sb_out = 8'hcb; 8'h5a: sb_out = 8'hbe; 8'h5b: sb_out = 8'h39;
            8'h5c: sb_out = 8'h4a; 8'h5d: sb_out = 8'h4c; 8'h5e: sb_out = 8'h58; 8'h5f: sb_out = 8'hcf;
            8'h60: sb_out = 8'hd0; 8'h61: sb_out = 8'hef; 8'h62: sb_out = 8'haa; 8'h63: sb_out = 8'hfb;
            8'h64: sb_out = 8'h43; 8'h65: sb_out = 8'h4d; 8'h66: sb_out = 8'h33; 8'h67: sb_out = 8'h85;
            8'h68: sb_out = 8'h45; 8'h69: sb_out = 8'hf9; 8'h6a: sb_out = 8'h02; 8'h6b: sb_out = 8'h7f;
            8'h6c: sb_out = 8'h50; 8'h6d: sb_out = 8'h3c; 8'h6e: sb_out = 8'h9f; 8'h6f: sb_out = 8'ha8;
            8'h70: sb_out = 8'h51; 8'h71: sb_out = 8'ha3; 8'h72: sb_out = 8'h40; 8'h73: sb_out = 8'h8f;
            8'h74: sb_out = 8'h92; 8'h75: sb_out = 8'h9d; 8'h76: sb_out = 8'h38; 8'h77: sb_out = 8'hf5;
            8'h78: sb_out = 8'hbc; 8'h79: sb_out = 8'hb6; 8'h7a: sb_out = 8'hda; 8'h7b: sb_out = 8'h21;
            8'h7c: sb_out = 8'h10; 8'h7d: sb_out = 8'hff; 8'h7e: sb_out = 8'hf3; 8'h7f: sb_out = 8'hd2;
            8'h80: sb_out = 8'hcd; 8'h81: sb_out = 8'h0c; 8'h82: sb_out = 8'h13; 8'h83: sb_out = 8'hec;
            8'h84: sb_out = 8'h5f; 8'h85: sb_out = 8'h97; 8'h86: sb_out = 8'h44; 8'h87: sb_out = 8'h17;
            8'h88: sb_out = 8'hc4; 8'h89: sb_out = 8'ha7; 8'h8a: sb_out = 8'h7e; 8'h8b: sb_out = 8'h3d;
            8'h8c: sb_out = 8'h64; 8'h8d: sb_out = 8'h5d; 8'h8e: sb_out = 8'h19; 8'h8f: sb_out = 8'h73;
            8'h90: sb_out = 8'h60; 8'h91: sb_out = 8'h81; 8'h92: sb_out = 8'h4f; 8'h93: sb_out = 8'hdc;
            8'h94: sb_out = 8'h22; 8'h95: sb_out = 8'h2a; 8'h96: sb_out = 8'h90; 8'h97: sb_out = 8'h88;
            8'h98: sb_out = 8'h46; 8'h99: sb_out = 8'hee; 8'h9a: sb_out = 8'hb8; 8'h9b: sb_out = 8'h14;
            8'h9c: sb_out = 8'hde; 8'h9d: sb_out = 8'h5e; 8'h9e: sb_out = 8'h0b; 8'h9f: sb_out = 8'hdb;
            8'ha0: sb_out = 8'he0; 8'ha1: sb_out = 8'h32; 8'ha2: sb_out = 8'h3a; 8'ha3: sb_out = 8'h0a;
            8'ha4: sb_out = 8'h49; 8'ha5: sb_out = 8'h06; 8'ha6: sb_out = 8'h24; 8'ha7: sb_out = 8'h5c;
            8'ha8: sb_out = 8'hc2; 8'ha9: sb_out = 8'hd3; 8'haa: sb_out = 8'hac; 8'hab: sb_out = 8'h62;
            8'hac: sb_out = 8'h91; 8'had: sb_out = 8'h95; 8'hae: sb_out = 8'he4; 8'haf: sb_out = 8'h79;
            8'hb0: sb_out = 8'he7; 8'hb1: sb_out = 8'hc8; 8'hb2: sb_out = 8'h37; 8'hb3: sb_out = 8'h6d;
            8'hb4: sb_out = 8'h8d; 8'hb5: sb_out = 8'hd5; 8'hb6: sb_out = 8'h4e; 8'hb7: sb_out = 8'ha9;
            8'hb8: sb_out = 8'h6c; 8'hb9: sb_out = 8'h56; 8'hba: sb_out = 8'hf4; 8'hbb: sb_out = 8'hea;
            8'hbc: sb_out = 8'h65; 8'hbd: sb_out = 8'h7a; 8'hbe: sb_out = 8'hae; 8'hbf: sb_out = 8'h08;
            8'hc0: sb_out = 8'hba; 8'hc1: sb_out = 8'h78; 8'hc2: sb_out = 8'h25; 8'hc3: sb_out = 8'h2e;
            8'hc4: sb_out = 8'h1c; 8'hc5: sb_out = 8'ha6; 8'hc6: sb_out = 8'hb4; 8'hc7: sb_out = 8'hc6;
            8'hc8: sb_out = 8'he8; 8'hc9: sb_out = 8'hdd; 8'hca: sb_out = 8'h74; 8'hcb: sb_out = 8'h1f;
            8'hcc: sb_out = 8'h4b; 8'hcd: sb_out = 8'hbd; 8'hce: sb_out = 8'h8b; 8'hcf: sb_out = 8'h8a;
            8'hd0: sb_out = 8'h70; 8'hd1: sb_out = 8'h3e; 8'hd2: sb_out = 8'hb5; 8'hd3: sb_out = 8'h66;
            8'hd4: sb_out = 8'h48; 8'hd5: sb_out = 8'h03; 8'hd6: sb_out = 8'hf6; 8'hd7: sb_out = 8'h0e;
            8'hd8: sb_out = 8'h61; 8'hd9: sb_out = 8'h35; 8'hda: sb_out = 8'h57; 8'hdb: sb_out = 8'hb9;
            8'hdc: sb_out = 8'h86; 8'hdd: sb_out = 8'hc1; 8'hde: sb_out = 8'h1d; 8'hdf: sb_out = 8'h9e;
            8'he0: sb_out = 8'he1; 8'he1: sb_out = 8'hf8; 8'he2: sb_out = 8'h98; 8'he3: sb_out = 8'h11;
            8'he4: sb_out = 8'h69; 8'he5: sb_out = 8'hd9; 8'he6: sb_out = 8'h8e; 8'he7: sb_out = 8'h94;
            8'he8: sb_out = 8'h9b; 8'he9: sb_out = 8'h1e; 8'hea: sb_out = 8'h87; 8'heb: sb_out = 8'he9;
            8'hec: sb_out = 8'hce; 8'hed: sb_out = 8'h55; 8'hee: sb_out = 8'h28; 8'hef: sb_out = 8'hdf;
            8'hf0: sb_out = 8'h8c; 8'hf1: sb_out = 8'ha1; 8'hf2: sb_out = 8'h89; 8'hf3: sb_out = 8'h0d;
            8'hf4: sb_out = 8'hbf; 8'hf5: sb_out = 8'he6; 8'hf6: sb_out = 8'h42; 8'hf7: sb_out = 8'h68;
            8'hf8: sb_out = 8'h41; 8'hf9: sb_out = 8'h99; 8'hfa: sb_out = 8'h2d; 8'hfb: sb_out = 8'h0f;
            8'hfc: sb_out = 8'hb0; 8'hfd: sb_out = 8'h54; 8'hfe: sb_out = 8'hbb; 8'hff: sb_out = 8'h16;
        endcase
    end

    // ------------------------------------------------------------------------
    // MixColumn forward on the single sbox byte s:
    //   xtime(s)  = (s << 1) ^ (s[7] ? 8'h1b : 0)
    //   word_le   = { 3*s, 1*s, 1*s, 2*s }   (byte0 = 2*s, byte3 = 3*s)
    // where 3*s = xtime(s) ^ s.
    // ------------------------------------------------------------------------
    logic [7:0] xtime_s;
    logic [7:0] three_s;
    assign xtime_s = {sb_out[6:0], 1'b0} ^ (sb_out[7] ? 8'h1b : 8'h00);
    assign three_s = xtime_s ^ sb_out;

    logic [31:0] mixcol_word;
    assign mixcol_word = {three_s, sb_out, sb_out, xtime_s};

    // ------------------------------------------------------------------------
    // Rotate-left by bs*8 bits  (barrel shift over the four byte positions)
    // ------------------------------------------------------------------------
    logic [31:0] rotated;
    always_comb begin
        unique case (bs_i)
            2'd0: rotated =  mixcol_word;
            2'd1: rotated = {mixcol_word[23:0], mixcol_word[31:24]};
            2'd2: rotated = {mixcol_word[15:0], mixcol_word[31:16]};
            2'd3: rotated = {mixcol_word[ 7:0], mixcol_word[31: 8]};
        endcase
    end

    // ------------------------------------------------------------------------
    // Final XOR with rs1
    // ------------------------------------------------------------------------
    assign result_o = rs1_i ^ rotated;

endmodule
