module rv32_branch_unit (
  input logic is_branch,
  input logic [2:0] br_funct3,
  input logic is_jal,
  input logic is_jalr,
  input logic [31:0] pc,
  input logic [31:0] rs1,
  input logic [31:0] rs2,
  input logic [31:0] imm,
  output logic took,
  output logic [31:0] target
);
  logic signed [31:0] rs1s, rs2s;

  always_comb begin
    rs1s = $signed(rs1);
    rs2s = $signed(rs2);

    took = 1'b0;
    target = pc + 32'd4;

    // jumps
    if (is_jal) begin
      took = 1'b1;
      target = pc + imm;
    end else if (is_jalr) begin
      took = 1'b1;
      target = (rs1 + imm) & 32'hFFFF_FFFE; // clr lsb
    end else if (is_branch) begin
      unique case (br_funct3)
        3'b000: took = (rs1 == rs2); // beq
        3'b001: took = (rs1 != rs2); // bne
        3'b100: took = (rs1s < rs2s); // blt
        3'b101: took = (rs1s >= rs2s); // bge
        3'b110: took = (rs1 < rs2); // bltu
        3'b111: took = (rs1 >= rs2); // bgeu
        default: took = 1'b0;
      endcase
      target = pc + imm;
    end
  end
endmodule