module rv32_decode (
  input logic [31:0] instr,

  output logic regwrite,
  output rv32_pkg::wb_sel_e wb_sel,

  output logic memread,
  output logic memwrite,
  output logic [1:0] mem_size, // 0=byte,1=half,2=word
  output logic mem_sign, // 1=signed, 0=unsigned

  output rv32_pkg::alu_op_e alu_op,
  output logic alu_src_imm,

  output logic is_branch,
  output logic [2:0] br_funct3,

  output logic is_jal,
  output logic is_jalr,

  output logic [31:0] imm
);
  import rv32_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  function automatic logic [31:0] imm_i(input logic [31:0] i);
    imm_i = {{20{i[31]}}, i[31:20]};
  endfunction

  function automatic logic [31:0] imm_s(input logic [31:0] i);
    imm_s = {{20{i[31]}}, i[31:25], i[11:7]};
  endfunction

  function automatic logic [31:0] imm_b(input logic [31:0] i);
    imm_b = {{19{i[31]}}, i[31], i[7], i[30:25], i[11:8], 1'b0};
  endfunction

  function automatic logic [31:0] imm_u(input logic [31:0] i);
    imm_u = {i[31:12], 12'b0};
  endfunction

  function automatic logic [31:0] imm_j(input logic [31:0] i);
    imm_j = {{11{i[31]}}, i[31], i[19:12], i[20], i[30:21], 1'b0};
  endfunction

  always_comb begin
    opcode = instr[6:0];
    funct3 = instr[14:12];
    funct7 = instr[31:25];

    // safe defaults (nop)
    regwrite = 1'b0;
    wb_sel = WB_NONE;

    memread = 1'b0;
    memwrite = 1'b0;
    mem_size = 2'd2; // word
    mem_sign = 1'b1;

    alu_op = ALU_ADD;
    alu_src_imm = 1'b0;

    is_branch = 1'b0;
    br_funct3 = funct3;

    is_jal = 1'b0;
    is_jalr = 1'b0;

    imm = 32'd0;

    unique case (opcode)

      // lui
      7'b0110111: begin
        regwrite = 1'b1;
        wb_sel = WB_ALU; // core should force op_a=0 for lui
        alu_op = ALU_ADD;
        alu_src_imm = 1'b1;
        imm = imm_u(instr);
      end

      // auipc
      7'b0010111: begin
        regwrite = 1'b1;
        wb_sel = WB_ALU; // core should force op_a=pc for auipc
        alu_op = ALU_ADD;
        alu_src_imm = 1'b1;
        imm = imm_u(instr);
      end

      // jal
      7'b1101111: begin
        regwrite = 1'b1;
        wb_sel = WB_PC4;
        is_jal = 1'b1;
        imm = imm_j(instr);
      end

      // jalr
      7'b1100111: begin
        regwrite = 1'b1;
        wb_sel = WB_PC4;
        is_jalr = 1'b1;
        alu_op = ALU_ADD;
        alu_src_imm = 1'b1;
        imm = imm_i(instr);
      end

      // branch
      7'b1100011: begin
        is_branch = 1'b1;
        br_funct3 = funct3;
        imm = imm_b(instr);
        // alu not required here; branch unit compares rs1/rs2
      end

      // load
      7'b0000011: begin
        regwrite = 1'b1;
        wb_sel = WB_MEM;
        memread = 1'b1;
        alu_op = ALU_ADD;
        alu_src_imm = 1'b1;
        imm = imm_i(instr);

        unique case (funct3)
          3'b000: begin mem_size = 2'd0; mem_sign = 1'b1; end // lb
          3'b001: begin mem_size = 2'd1; mem_sign = 1'b1; end // lh
          3'b010: begin mem_size = 2'd2; mem_sign = 1'b1; end // lw
          3'b100: begin mem_size = 2'd0; mem_sign = 1'b0; end // lbu
          3'b101: begin mem_size = 2'd1; mem_sign = 1'b0; end // lhu
          default: begin
            // illegal/unsupported -> nop
            regwrite = 1'b0; memread = 1'b0; wb_sel = WB_NONE;
          end
        endcase
      end

      // store
      7'b0100011: begin
        memwrite = 1'b1;
        alu_op = ALU_ADD;
        alu_src_imm = 1'b1;
        imm = imm_s(instr);

        unique case (funct3)
          3'b000: mem_size = 2'd0; // sb
          3'b001: mem_size = 2'd1; // sh
          3'b010: mem_size = 2'd2; // sw
          default: begin
            memwrite = 1'b0;
          end
        endcase
      end

      // op-imm
      7'b0010011: begin
        regwrite = 1'b1;
        wb_sel = WB_ALU;
        alu_src_imm = 1'b1;
        imm = imm_i(instr);

        unique case (funct3)
          3'b000: alu_op = ALU_ADD; // addi
          3'b010: alu_op = ALU_SLT; // slti
          3'b011: alu_op = ALU_SLTU; // sltiu
          3'b100: alu_op = ALU_XOR; // xori
          3'b110: alu_op = ALU_OR; // ori
          3'b111: alu_op = ALU_AND; // andi
          3'b001: alu_op = ALU_SLL; // slli
          3'b101: begin
            // srli/srai determined by instr[30]
            alu_op = (instr[30] == 1'b1) ? ALU_SRA : ALU_SRL;
          end
          default: begin
            regwrite = 1'b0; wb_sel = WB_NONE;
          end
        endcase
      end

      // op (r-type)
      7'b0110011: begin
        regwrite = 1'b1;
        wb_sel = WB_ALU;
        alu_src_imm = 1'b0;

        unique case (funct3)
          3'b000: alu_op = (funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: alu_op = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          default: begin
            regwrite = 1'b0; wb_sel = WB_NONE;
          end
        endcase
      end

      default: begin
        // unsupported -> nop
      end
    endcase
  end
endmodule