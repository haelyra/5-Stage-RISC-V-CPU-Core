module rv32_memmap (
  input logic [31:0] addr,
  output logic is_mmio,
  output logic mmio_we,
  output logic [31:0] mmio_addr
);
  always_comb begin
    // default: nothing
    is_mmio = 1'b0;
    mmio_we = 1'b0;
    mmio_addr = addr;

    // simple region decode: top nibble == 0xf
    if (addr[31:28] == 4'hF) begin
      is_mmio = 1'b1;
      // mmio_we is intentionally left 0 here; core should and memwrite into it
      mmio_we = 1'b0;
    end
  end
endmodule