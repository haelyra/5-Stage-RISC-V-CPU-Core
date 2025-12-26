`timescale 1ns/1ps

module tb_top;

  // clk / reset
  logic clk;
  logic rst_n;

  localparam time CLK_HALF = 5ns; // 100 mhz

  initial begin
    clk = 1'b0;
    forever #CLK_HALF clk = ~clk;
  end

  task automatic do_reset();
    begin
      rst_n = 1'b0;
      repeat (10) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  // dut interface wires
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_valid;
  logic        dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0]  dmem_wstrb;
  logic        dmem_ready;
  logic [31:0] dmem_rdata;

  logic        mmio_we;
  logic [31:0] mmio_addr;
  logic [31:0] mmio_wdata;
  logic [31:0] mmio_rdata;

  // instantiate dut
  rv32_core dut (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .dmem_valid(dmem_valid),
    .dmem_we(dmem_we),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wstrb(dmem_wstrb),
    .dmem_ready(dmem_ready),
    .dmem_rdata(dmem_rdata),

    .mmio_we(mmio_we),
    .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata),
    .mmio_rdata(mmio_rdata)
  );

  // imem model
  localparam int IMEM_WORDS = 16384; // 64kb
  logic [31:0] imem [0:IMEM_WORDS-1];

  // instruction fetch: word addressed
  always_comb begin
    imem_rdata = imem[imem_addr[31:2]];
  end

  // load program via +imem=path.hex
  initial begin
    string imem_file;
    if ($value$plusargs("IMEM=%s", imem_file)) begin
      $display("[TB] Loading IMEM from %s", imem_file);
      $readmemh(imem_file, imem);
    end else begin
      $display("[TB] No +IMEM=... provided. IMEM will be zeros (NOPs).");
    end
  end

  // dmem
  localparam int DMEM_WORDS = 16384; // 64kb
  logic [31:0] dmem [0:DMEM_WORDS-1];

  initial begin
    dmem_ready = 1'b1; // simplify: always ready
  end

  // read: word read
  always_comb begin
    dmem_rdata = dmem[dmem_addr[31:2]];
  end

  // write with byte strobes
  always_ff @(posedge clk) begin
    if (rst_n && dmem_valid && dmem_we) begin
      logic [31:0] cur;
      cur = dmem[dmem_addr[31:2]];

      if (dmem_wstrb[0]) cur[7:0] = dmem_wdata[7:0];
      if (dmem_wstrb[1]) cur[15:8] = dmem_wdata[15:8];
      if (dmem_wstrb[2]) cur[23:16] = dmem_wdata[23:16];
      if (dmem_wstrb[3]) cur[31:24] = dmem_wdata[31:24];

      dmem[dmem_addr[31:2]] <= cur;

      $display("[TB][DMEM] W addr=%08x wdata=%08x wstrb=%b", dmem_addr, dmem_wdata, dmem_wstrb);
    end
  end

  // optional: preload dmem via +dmem=path.hex
  initial begin
    string dmem_file;
    if ($value$plusargs("DMEM=%s", dmem_file)) begin
      $display("[TB] Loading DMEM from %s", dmem_file);
      $readmemh(dmem_file, dmem);
    end
  end

  // mmio model + tohost
  logic [31:0] tohost;

  localparam logic [31:0] TOHOST_ADDR = 32'hF000_0000;

  always_comb begin
    // default mmio read
    mmio_rdata = 32'd0;
    if (mmio_addr == TOHOST_ADDR) begin
      mmio_rdata = tohost;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tohost <= 32'd0;
    end else begin
      if (mmio_we) begin
        $display("[TB][MMIO] W addr=%08x data=%08x", mmio_addr, mmio_wdata);
        if (mmio_addr == TOHOST_ADDR) begin
          tohost <= mmio_wdata;
        end
      end
    end
  end

  // run control / pass-fail
  localparam int MAX_CYCLES = 200000;

  initial begin
    $display("[TB] Starting...");
    do_reset();

    // run until pass/fail or timeout
    for (int cyc = 0; cyc < MAX_CYCLES; cyc++) begin
      @(posedge clk);

      if (tohost != 32'd0) begin
        if (tohost == 32'd1) begin
          $display("[TB] PASS (tohost==1) at cycle %0d", cyc);
          $finish;
        end else begin
          $display("[TB] FAIL (tohost=%0d / 0x%08x) at cycle %0d", tohost, tohost, cyc);
          $fatal(1);
        end
      end
    end

    $display("[TB] TIMEOUT after %0d cycles", MAX_CYCLES);
    $fatal(1);
  end

endmodule