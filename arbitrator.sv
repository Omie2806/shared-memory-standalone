module arbitrator #(
    parameter BANKS      = 16,
    parameter DW         = 16,
    parameter NUMBER_OF_THREADS  = 16, //systolic grid size 
    parameter ADDR_DEPTH = 16
) (
    input logic clk,
    input logic reset, 
    input logic matmul,
    input logic mem_write,
    input logic mem_req,
    input logic[NUMBER_OF_THREADS - 1 : 0] active_mask,
    input logic[ADDR_DEPTH - 1 : 0]        addr[0 : NUMBER_OF_THREADS - 1], // receive te whole address ad decode it here 
    input  logic [DW - 1 : 0]              data_in[0 : NUMBER_OF_THREADS - 1],
    output logic[DW -  1 : 0]              data_out[0 : NUMBER_OF_THREADS - 1],  
    output logic stall
);
    logic[ADDR_DEPTH - 1 : 0] saved_addr [0 : NUMBER_OF_THREADS - 1];
    logic[ADDR_DEPTH - 1 : 0] addr_depth [0 : NUMBER_OF_THREADS - 1];
    logic[ADDR_DEPTH - 1 : 0] addr_bank  [0 : NUMBER_OF_THREADS - 1];
    logic[DW - 1 : 0] read_data [0 : NUMBER_OF_THREADS - 1];

    logic[NUMBER_OF_THREADS - 1 : 0] bank_request [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] grant [0 : NUMBER_OF_THREADS - 1];
    //i might have to design a fifo for 16 registers(worst case when all req for a single bank).
    //saving the address and then accessing the data from the stalled register files
    //the conflict counter should be for all 16 banks imo 
    // logic [3 : 0]current_grant[0 : NUMBER_OF_THREADS - 1];
    logic grant_found;
    logic[0 : NUMBER_OF_THREADS - 1] grant_mask;
    // logic [3 : 0] grant_pointer;
    
    always_comb begin 
        if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                addr_bank[i]  = addr[i][3 : 0]; //bank address
                addr_depth[i] = addr[i][7 : 4]; //depth address        
            end
        end
    end
//i have to generate grants to individual threads to write in a specific bank
    always_ff @(posedge clk) begin
        if(reset) begin
            for (integer i = 0; i < BANKS; i++) begin
                grant[i]    <= 0;
                bank_request[i] <= 'b0;
                grant_mask = 16'h00;
            end
        end
        else if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < BANKS; j++) begin
                    bank_request[i][j] <= (addr_bank[j] == i); //which threads are requesting which bank
                end
            end            
        end
        else begin
            for(integer h = 0; h < BANKS; h++) begin
                for (integer i = 0; i < BANKS; i++) begin
                    grant_found = 0;
                    for(integer j = 0; j < BANKS; j++) begin
                        if(bank_request[i][j] && !grant_found) begin
                            grant[i]   <= j; //jth thread wants to access the first bank and so on
                            grant_found = 1;
                            bank_request[i][j] <= 0;
                            grant_mask[i] <= 1'b1;
                        end
                        else if(bank_request[i][j] == 0 && !grant_found) begin
                            grant[i] <= 0;
                            grant_mask[i] <= 0;
                        end
                    end                
                end            
            end
        end
    end

//i might have to use a bank active signal to enable specific bank/banks depending upon the bank address
//ig the total bus width should be DW*16 and each bank bus width should be 16
    genvar i;
    generate
        for (i = 0; i < BANKS; i++) begin   
            memory_bank mem_bank (
                .bank_en(addr_bank[grant[i]] == i[3 : 0] && active_mask[grant[i]] == 1), //comparison to check if bank number equals the address(this is wrong tho)
                .clk(clk),
                .reset(reset),
                .matmul(matmul),
                .mem_write(mem_write),
                .addr_depth(addr_depth[grant[i]]),
                .data_in(data_in[grant[i]]),
                .data_out(read_data[i]) //idk why it isnt allowing me to use grant[i] here
            );
        end
    endgenerate

    always_comb begin 
        for (integer i = 0; i < BANKS; i++) begin
            data_out[i] = 'b0;
        end
        for (integer i = 0; i < BANKS; i++) begin
            if(grant_mask[i]) begin
                data_out[grant[i]] = read_data[i];
            end
        end 
    end
endmodule