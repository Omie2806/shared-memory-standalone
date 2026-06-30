module memory_bank #(
    parameter DW         = 16,
    parameter ADDR_DEPTH = 4,
    parameter N          = 4
) (
    input logic clk,
    input logic reset,
    input logic bank_en,
    input logic mem_write,
    input logic matmul, //fromm control unit to know whether to actual perform matmul or not
    input logic[ADDR_DEPTH - 1 : 0] addr_depth, // 7 : 4 of the overall address
    input logic [DW - 1 : 0] data_in,
    output logic[DW - 1 : 0] data_out
);

reg [DW - 1 : 0] MEMORY_BANK [0 : 15];//16 REGISTERS PER BANK FOR DW AND 16 BANKS IN TOTAL
//lower address bits for bank and remaining for bank offset(8 bits total)
always_ff @(posedge clk) begin
    if(reset) begin
        for (integer  i = 0; i < 16; i++) begin
           MEMORY_BANK[i] <= 0; 
        end
    end
    else if(mem_write && bank_en) begin
       MEMORY_BANK[addr_depth] <= data_in; 
    end
end 

assign data_out = bank_en ? MEMORY_BANK[addr_depth] : 0;
endmodule
