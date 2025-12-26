module rv32_forward (
  input logic [4:0] idex_rs1,
  input logic [4:0] idex_rs2,

  input logic exmem_regwrite,
  input logic [4:0] exmem_rd,

  input logic memwb_regwrite,
  input logic [4:0] memwb_rd,

  output logic [1:0] fwd_a_sel,
  output logic [1:0] fwd_b_sel
);
  always_comb begin
    fwd_a_sel = 2'b00;
    fwd_b_sel = 2'b00;

    if (exmem_regwrite && (exmem_rd != 5'd0) && (exmem_rd == idex_rs1)) fwd_a_sel = 2'b01;
    else if (memwb_regwrite && (memwb_rd != 5'd0) && (memwb_rd == idex_rs1)) fwd_a_sel = 2'b10;

    if (exmem_regwrite && (exmem_rd != 5'd0) && (exmem_rd == idex_rs2)) fwd_b_sel = 2'b01;
    else if (memwb_regwrite && (memwb_rd != 5'd0) && (memwb_rd == idex_rs2)) fwd_b_sel = 2'b10;
  end
endmodule