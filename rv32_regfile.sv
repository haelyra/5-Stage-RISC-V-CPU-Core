module rv32_regfile (
  input logic clk,
  input logic rst_n,

  input logic [4:0] raddr1,
  input logic [4:0] raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2,

  input logic we,
  input logic [4:0] waddr,
  input logic [31:0] wdata
);
  logic [31:0] regs [31:0];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
    end else begin
      if (we && (waddr != 5'd0)) regs[waddr] <= wdata;
      regs[5'd0] <= 32'd0;
    end
  end

  always_comb begin
    rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
    rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];
  end
endmodule