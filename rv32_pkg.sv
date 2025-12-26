package rv32_pkg;
  typedef logic [31:0] u32;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
    ALU_SLT, ALU_SLTU, ALU_SLL, ALU_SRL, ALU_SRA
  } alu_op_e;

  typedef enum logic [2:0] {WB_NONE, WB_ALU, WB_MEM, WB_PC4, WB_IMM} wb_sel_e;

  typedef struct packed {
    logic valid;

    u32 pc;
    u32 instr;

    logic [4:0] rs1, rs2, rd;
    u32 rs1_val, rs2_val;
    u32 imm;

    // control
    logic regwrite;
    wb_sel_e wb_sel;

    logic memread;
    logic memwrite;
    logic [1:0] mem_size; // 0=byte,1=half,2=word
    logic mem_sign; // for loads

    logic is_branch;
    logic is_jal;
    logic is_jalr;
    logic [2:0] br_funct3;

    alu_op_e alu_op;
    logic alu_src_imm; // 1: op2=imm else rs2
  } idex_t;

  typedef struct packed {
    logic valid;

    u32 pc;
    u32 pc4;
    u32 alu_y;
    u32 rs2_fwd; // store data after forwarding

    logic [4:0] rd;

    logic regwrite;
    wb_sel_e wb_sel;

    logic memread;
    logic memwrite;
    logic [1:0] mem_size;
    logic mem_sign;

    // branch resolution info (optional for stats)
    logic took_branch;
    u32 br_target;
  } exmem_t;

  typedef struct packed {
    logic valid;

    u32 pc4;
    u32 alu_y;
    u32 mem_rdata;

    logic [4:0] rd;

    logic regwrite;
    wb_sel_e wb_sel;
  } memwb_t;

endpackage