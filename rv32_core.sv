module rv32_core (
  input logic clk,
  input logic rst_n,

  // imem
  output logic [31:0] imem_addr,
  input logic [31:0] imem_rdata,

  // dmem
  output logic dmem_valid,
  output logic dmem_we,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0] dmem_wstrb,
  input logic dmem_ready,
  input logic [31:0] dmem_rdata,

  // mmio
  output logic mmio_we,
  output logic [31:0] mmio_addr,
  output logic [31:0] mmio_wdata,
  input logic [31:0] mmio_rdata
);
  import rv32_pkg::*;

  // if stage
  u32 pc_q, pc_d;
  u32 if_pc4;
  u32 if_instr;

  // if/id pipeline reg
  logic ifid_valid_q, ifid_valid_d;
  u32 ifid_pc_q, ifid_pc_d;
  u32 ifid_instr_q, ifid_instr_d;

  // id/ex, ex/mem, mem/wb regs
  idex_t idex_q, idex_d;
  exmem_t exmem_q, exmem_d;
  memwb_t memwb_q, memwb_d;

  // regfile wires
  logic [4:0] rs1, rs2, rd;
  u32 rs1_val, rs2_val;

  // decode outputs
  logic dec_regwrite, dec_memread, dec_memwrite;
  logic [1:0] dec_mem_size;
  logic dec_mem_sign;
  wb_sel_e dec_wb_sel;
  alu_op_e dec_alu_op;
  logic dec_alu_src_imm;
  logic dec_is_branch, dec_is_jal, dec_is_jalr;
  logic [2:0] dec_br_funct3;
  u32 dec_imm;

  // hazard/forward control
  logic stall_if, stall_id;
  logic flush_ifid, flush_idex;
  logic [1:0] fwd_a_sel, fwd_b_sel; // 00=idex, 01=exmem, 10=memwb

  // ex stage wires
  u32 ex_op_a, ex_op_b, ex_op_b_raw;
  u32 alu_y;
  logic took_branch;
  u32 br_target;
  u32 pc_next_seq;

  // wb wires
  u32 wb_data;

  // pc/if
  assign imem_addr = pc_q;
  assign if_instr = imem_rdata;
  assign if_pc4 = pc_q + 32'd4;

  // default next pc is sequential
  assign pc_next_seq = if_pc4;

  // decode rs fields
  assign rs1 = ifid_instr_q[19:15];
  assign rs2 = ifid_instr_q[24:20];
  assign rd = ifid_instr_q[11:7];

  rv32_regfile u_rf (
    .clk(clk), .rst_n(rst_n),
    .raddr1(rs1), .raddr2(rs2),
    .rdata1(rs1_val), .rdata2(rs2_val),
    .we(memwb_q.regwrite && memwb_q.valid),
    .waddr(memwb_q.rd),
    .wdata(wb_data)
  );

  rv32_decode u_dec (
    .instr(ifid_instr_q),
    .regwrite(dec_regwrite),
    .wb_sel(dec_wb_sel),
    .memread(dec_memread),
    .memwrite(dec_memwrite),
    .mem_size(dec_mem_size),
    .mem_sign(dec_mem_sign),
    .alu_op(dec_alu_op),
    .alu_src_imm(dec_alu_src_imm),
    .is_branch(dec_is_branch),
    .br_funct3(dec_br_funct3),
    .is_jal(dec_is_jal),
    .is_jalr(dec_is_jalr),
    .imm(dec_imm)
  );

  // hazard + forward units
  rv32_hazard u_haz (
    .ifid_valid(ifid_valid_q),
    .idex_valid(idex_q.valid),
    .idex_memread(idex_q.memread),
    .ifid_rs1(rs1),
    .ifid_rs2(rs2),
    .idex_rd(idex_q.rd),
    .stall_if(stall_if),
    .stall_id(stall_id)
  );

  rv32_forward u_fwd (
    .idex_rs1(idex_q.rs1),
    .idex_rs2(idex_q.rs2),
    .exmem_regwrite(exmem_q.regwrite && exmem_q.valid),
    .exmem_rd(exmem_q.rd),
    .memwb_regwrite(memwb_q.regwrite && memwb_q.valid),
    .memwb_rd(memwb_q.rd),
    .fwd_a_sel(fwd_a_sel),
    .fwd_b_sel(fwd_b_sel)
  );

  // flush rules
  always_comb begin
    flush_ifid = took_branch;
    flush_idex = took_branch;
  end

  // id/ex latch inputs
  always_comb begin
    idex_d = '0;
    idex_d.valid = ifid_valid_q && !flush_idex && !stall_id;

    idex_d.pc = ifid_pc_q;
    idex_d.instr = ifid_instr_q;

    idex_d.rs1 = rs1;
    idex_d.rs2 = rs2;
    idex_d.rd = rd;
    idex_d.rs1_val = rs1_val;
    idex_d.rs2_val = rs2_val;
    idex_d.imm = dec_imm;

    idex_d.regwrite = dec_regwrite;
    idex_d.wb_sel = dec_wb_sel;

    idex_d.memread = dec_memread;
    idex_d.memwrite = dec_memwrite;
    idex_d.mem_size = dec_mem_size;
    idex_d.mem_sign = dec_mem_sign;

    idex_d.is_branch = dec_is_branch;
    idex_d.br_funct3 = dec_br_funct3;
    idex_d.is_jal = dec_is_jal;
    idex_d.is_jalr = dec_is_jalr;

    idex_d.alu_op = dec_alu_op;
    idex_d.alu_src_imm = dec_alu_src_imm;

    if (stall_id) begin
      // insert bubble
      idex_d = '0;
    end
  end

  // ex: forwarding muxes + alu + branch/jump resolve
  logic [6:0] ex_opcode;
  assign ex_opcode = idex_q.instr[6:0];

  always_comb begin
    // defaults
    ex_op_a = idex_q.rs1_val;
    if (ex_opcode == 7'b0110111) begin
      // lui: op_a must be 0
      ex_op_a = 32'd0;
    end else if (ex_opcode == 7'b0010111) begin
      // auipc: op_a must be pc
      ex_op_a = idex_q.pc;
    end
    ex_op_b_raw = idex_q.rs2_val;

    case (fwd_a_sel)
      2'b01: ex_op_a = exmem_q.alu_y;
      2'b10: ex_op_a = wb_data;
      default: /*00*/ ;
    endcase

    case (fwd_b_sel)
      2'b01: ex_op_b_raw = exmem_q.alu_y;
      2'b10: ex_op_b_raw = wb_data;
      default: /*00*/ ;
    endcase
  end

  assign ex_op_b = (idex_q.alu_src_imm) ? idex_q.imm : ex_op_b_raw;

  rv32_alu u_alu (
    .op(idex_q.alu_op),
    .a(ex_op_a),
    .b(ex_op_b),
    .y(alu_y)
  );

  // branch/jump decision in ex
  rv32_branch_unit u_bru (
    .is_branch(idex_q.is_branch),
    .br_funct3(idex_q.br_funct3),
    .is_jal(idex_q.is_jal),
    .is_jalr(idex_q.is_jalr),
    .pc(idex_q.pc),
    .rs1(ex_op_a),
    .rs2(ex_op_b_raw),
    .imm(idex_q.imm),
    .took(took_branch),
    .target(br_target)
  );

  // pc update
  always_comb begin
    pc_d = pc_q;
    if (!stall_if) begin
      pc_d = took_branch ? br_target : pc_next_seq;
    end
  end

  // ex/mem latch
  always_comb begin
    exmem_d = '0;
    exmem_d.valid = idex_q.valid;

    exmem_d.pc4 = idex_q.pc + 32'd4;
    exmem_d.alu_y = alu_y;
    exmem_d.rs2_fwd = ex_op_b_raw;

    exmem_d.rd = idex_q.rd;

    exmem_d.regwrite = idex_q.regwrite;
    exmem_d.wb_sel = idex_q.wb_sel;

    exmem_d.memread = idex_q.memread;
    exmem_d.memwrite = idex_q.memwrite;
    exmem_d.mem_size = idex_q.mem_size;
    exmem_d.mem_sign = idex_q.mem_sign;

    exmem_d.took_branch = took_branch;
    exmem_d.br_target = br_target;
  end

  // mem stage: dmem + mmio decode
  rv32_memmap u_mm (
    .addr(exmem_q.alu_y),
    .is_mmio(/*out*/),
    .mmio_we(mmio_we),
    .mmio_addr(mmio_addr)
  );

  // mem/wb latch
  always_comb begin
    memwb_d = '0;
    memwb_d.valid = exmem_q.valid;

    memwb_d.pc4 = exmem_q.pc4;
    memwb_d.alu_y = exmem_q.alu_y;
    memwb_d.mem_rdata = 32'd0;

    memwb_d.rd = exmem_q.rd;
    memwb_d.regwrite = exmem_q.regwrite;
    memwb_d.wb_sel = exmem_q.wb_sel;
  end

  // wb mux
  always_comb begin
    wb_data = 32'd0;
    unique case (memwb_q.wb_sel)
      WB_ALU: wb_data = memwb_q.alu_y;
      WB_MEM: wb_data = memwb_q.mem_rdata;
      WB_PC4: wb_data = memwb_q.pc4;
      WB_IMM: wb_data = memwb_q.alu_y;
      default: wb_data = 32'd0;
    endcase
  end

  // pipeline registers
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc_q <= 32'd0;

      ifid_valid_q <= 1'b0;
      ifid_pc_q <= 32'd0;
      ifid_instr_q <= 32'd0;

      idex_q <= '0;
      exmem_q <= '0;
      memwb_q <= '0;
    end else begin
      // pc
      pc_q <= pc_d;

      // if/id
      if (!stall_if) begin
        ifid_valid_q <= 1'b1;
        ifid_pc_q <= pc_q;
        ifid_instr_q <= if_instr;
      end

      if (flush_ifid) begin
        ifid_valid_q <= 1'b0;
      end

      // id/ex, ex/mem, mem/wb
      idex_q <= idex_d;
      exmem_q <= exmem_d;
      memwb_q <= memwb_d;
    end
  end

endmodule