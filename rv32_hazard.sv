module rv32_hazard (
  input logic ifid_valid,
  input logic idex_valid,
  input logic idex_memread,
  input logic [4:0] ifid_rs1,
  input logic [4:0] ifid_rs2,
  input logic [4:0] idex_rd,
  output logic stall_if,
  output logic stall_id
);
  logic hazard;
  always_comb begin
    hazard = 1'b0;
    if (ifid_valid && idex_valid && idex_memread && (idex_rd != 5'd0)) begin
      if ((idex_rd == ifid_rs1) || (idex_rd == ifid_rs2)) hazard = 1'b1;
    end
    stall_if = hazard;
    stall_id = hazard;
  end
endmodule