module core_2_bram #(
    parameter R_LATENCY_IN_CYCLES = 1
)(
    input logic                       clk_i,
    input logic                       rst_ni,
    input  logic                      req_i,
    output logic                      gnt_o,
    output logic                      rvalid_o,
    input  logic  [31:0]              addr_i,
    input  logic                      we_i,
    input  logic  [3:0]               be_i,
    output logic  [31:0]              rdata_o,
    input  logic  [31:0]              wdata_i,

    output  logic [31:0]              addr,
    output  logic [31:0]              dout,
    input   logic [31:0]              din,
    output  logic [3:0]               weout
);

  localparam IDLE = 0, READ_WAIT = 1, WRITE_WAIT = 2;
  logic [1:0] state, next_state;
  logic        rvalid;

  // ---------- ASSIGNS ----------
  assign gnt_o   = req_i & (state != READ_WAIT | rvalid);
  assign rdata_o = din;
  assign addr    = addr_i;
  assign dout    = we_i ? wdata_i : '0;

  // ---------- STATE REGISTER ----------
  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      state <= IDLE;
    else
      state <= next_state;
  end

  // ---------- NEXT-STATE LOGIC ----------
  always_comb begin
    case (state)
      IDLE:       next_state = req_i  ? (we_i ? WRITE_WAIT : READ_WAIT) : IDLE;
      READ_WAIT:  next_state = rvalid ? (req_i ? (we_i ? WRITE_WAIT : READ_WAIT) : IDLE) : READ_WAIT;
      WRITE_WAIT: next_state = req_i  ? (we_i ? WRITE_WAIT : READ_WAIT) : IDLE;
      default:    next_state = IDLE;
    endcase
  end

  // ---------- OUTPUT LOGIC ----------
  always_comb begin
    weout    = (req_i & we_i) ? be_i : '0;
    rvalid_o = '0;
    case (state)
      IDLE:       rvalid_o = '0;
      READ_WAIT:  rvalid_o = rvalid;
      WRITE_WAIT: rvalid_o = 1'b1;
      default:    rvalid_o = '0;
    endcase
  end

  // ---------- READ LATENCY HANDLING ----------
  generate
    if (R_LATENCY_IN_CYCLES <= 1) begin : gen_lat_1

      assign rvalid = 1'b1;

    end else begin : gen_lat_n

      logic [$clog2(R_LATENCY_IN_CYCLES):0] lat_cnt;

      logic entering_read;
      logic restarting_read;
      assign entering_read    = (state != READ_WAIT) & (next_state == READ_WAIT);
      assign restarting_read  = (state == READ_WAIT) & rvalid & (next_state == READ_WAIT);

      always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
          lat_cnt <= '0;
        end else begin
          if (entering_read | restarting_read) begin
            lat_cnt <= R_LATENCY_IN_CYCLES - 1;
          end else if ((state == READ_WAIT) && (lat_cnt > 0)) begin
            lat_cnt <= lat_cnt - 1;
          end
        end
      end

      assign rvalid = (state == READ_WAIT) & (lat_cnt == 0);
    end
  endgenerate

endmodule