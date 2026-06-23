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
    logic[3 : 0] addr_depth [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] addr_bank  [0 : NUMBER_OF_THREADS - 1];
    logic[DW - 1 : 0] read_data [0 : NUMBER_OF_THREADS - 1];

    logic[NUMBER_OF_THREADS - 1 : 0] bank_request [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] grant [0 : NUMBER_OF_THREADS - 1];

    logic grant_found;
    logic[0 : NUMBER_OF_THREADS - 1] grant_mask;
    logic[3 : 0] broadcast [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] broadcast_bank [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] bank_to_read [0 : NUMBER_OF_THREADS - 1];
    logic is_broadcast[0 : NUMBER_OF_THREADS - 1];

    logic[3 : 0] debug_i [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] debug_j [0 : NUMBER_OF_THREADS - 1];

    //ill have to know when a memory request actually finishes only then i can clear broadcast

    logic any_pending;
    
    always_comb begin 
        if(reset) begin
            for (integer i = 0; i < BANKS; i++) begin
                broadcast[i] = 0;
                broadcast_bank[i] = 0; 
                stall = 0;
                debug_i[i] = 0;
                debug_j[i] = 0;
                is_broadcast[i] = 0;
            end            
        end
        if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                addr_bank[i]  = addr[i][3 : 0]; //bank address
                addr_depth[i] = addr[i][7 : 4]; //depth address 
            end
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < BANKS; j++) begin
                    if((i != j) && (addr_bank[i] == addr_bank[j]) && (addr_depth[i] == addr_depth[j]) && !mem_write) begin
                        broadcast[i] = i;
                        broadcast_bank[i] = addr_bank[i];
                        is_broadcast[i] = 1;
                    end
                end       
            end
        end
        any_pending = '0;
        for (integer i = 0; i < BANKS; i++) begin
            any_pending = any_pending | (|bank_request[i]); 
        end
        stall = any_pending;
        if(!stall && |grant_mask == 0) begin
            for(integer i = 0; i < BANKS; i++) begin
                broadcast[i] = 0;
                broadcast_bank[i] = 0;   
                is_broadcast[i] = 0;
            end     
        end
    end
//i have to generate grants to individual threads to write in a specific bank
    always_ff @(posedge clk) begin
        if(reset) begin
            for (integer i = 0; i < BANKS; i++) begin
                grant[i]    <= 0;
                bank_request[i] <= 'b0;
                grant_mask <= 16'h00;
                bank_to_read[i] <= 0;
            end
        end
        else if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < BANKS; j++) begin
                    bank_request[i][j] <= (addr_bank[j] == i); //which threads are requesting which bank
                    bank_to_read[i] <= addr_bank[i];
                end
            end            
        end
        else begin
            for (integer i = 0; i < BANKS; i++) begin
                grant_found = 0;
                for(integer j = 0; j < BANKS; j++) begin
                    if(bank_request[i][j]) begin
                        if(|broadcast[i] && (addr_depth[i] == addr_depth[j])) begin
                            bank_request[i][j] <= 0;
                            grant[i]      <= j;
                            grant_mask[i] <= 1'b1;
                        end
                        else if(!grant_found) begin
                            grant[i]   <= j; //jth thread wants to access the first bank and so on
                            grant_found = 1;
                            bank_request[i][j] <= 0;
                            grant_mask[i] <= 1'b1;
                        end
                    end
                    else if(bank_request[i] == 0 && |broadcast[i] == 0) begin
                        grant[i] <= 0;
                        grant_mask[i] <= 0;
                    end
                end              
            end                       
        end
    end

    genvar i;
    generate
        for (i = 0; i < BANKS; i++) begin   
            memory_bank mem_bank (
                .bank_en(addr_bank[grant[i]] == i[3 : 0] && active_mask[grant[i]] == 1 && grant_mask[i]), //comparison to check if bank number equals the address(this is wrong tho)
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
            if(grant_mask[i])begin
                data_out[grant[i]] = read_data[i];
                debug_j[i] = i;
            end            
        end
        for (integer i = 0; i < BANKS; i++) begin
            if(is_broadcast[i]) begin
                data_out[broadcast[i]] = read_data[broadcast_bank[i]];
                debug_i[i] = broadcast_bank[i]; 
            end
        end
    end
endmodule
