module rv32_alu (
  input rv32_pkg::alu_op_e op,
  input logic [31:0] a,
  input logic [31:0] b,
  output logic [31:0] y
);
  import rv32_pkg::*;

  logic signed [31:0] as, bs;

  always_comb begin
    as = $signed(a);
    bs = $signed(b);

    y = 32'd0;
    unique case (op)
      ALU_ADD : y = a + b;
      ALU_SUB : y = a - b;
      ALU_AND : y = a & b;
      ALU_OR  : y = a | b;
      ALU_XOR : y = a ^ b;

      ALU_SLT : y = (as < bs) ? 32'd1 : 32'd0;
      ALU_SLTU: y = (a  < b ) ? 32'd1 : 32'd0;

      ALU_SLL : y = a << b[4:0];
      ALU_SRL : y = a >> b[4:0];
      ALU_SRA : y = as >>> b[4:0];

      default : y = 32'd0;
    endcase
  end
endmodule