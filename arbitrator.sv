module arbitrator #(
    parameter BANKS      = 16,
    parameter DW         = 16,
    parameter NUMBER_OF_THREADS  = 16, //systolic grid size 
    parameter ADDR_DEPTH = 16
) (
    input logic clk,
    input logic reset, 
    input logic mem_write,
    input logic mem_req,
    input logic [NUMBER_OF_THREADS - 1 : 0]       active_mask,
    input logic [ADDR_DEPTH - 1 : 0]              addr[0 : NUMBER_OF_THREADS - 1], // receive te whole address ad decode it here 
    input  logic [DW - 1 : 0]                     data_in[0 : NUMBER_OF_THREADS - 1],
    output logic [DW -  1 : 0]                    data_out[0 : NUMBER_OF_THREADS - 1], 
    output logic stall
);
    logic[3 : 0] addr_depth [0 : NUMBER_OF_THREADS - 1];
    logic[3 : 0] addr_bank  [0 : NUMBER_OF_THREADS - 1];
    logic[DW - 1 : 0] read_data [0 : NUMBER_OF_THREADS - 1];
    
    logic[15 : 0] grant_mask_per_bank[0 : BANKS - 1][0 : ADDR_DEPTH - 1];
    //00-dont serve, 01- serve remaining, 10-serve done
    logic[1 : 0]  SERVE[0 : BANKS - 1][0 : ADDR_DEPTH - 1];
    logic         VALID[0 : BANKS - 1][0 : ADDR_DEPTH - 1];
    logic[15 : 0] current_grant;
    logic current_grant_found;
    logic valid_found;
    logic bank_grant[0 : BANKS - 1];
    logic[3 : 0] thread_to_read [0 : NUMBER_OF_THREADS - 1];

    logic any_pending;
    logic grant_left;
    logic[15 : 0] stall_cycles;
    typedef enum logic {
        FIRST = 0,
        SECOND = 1
    } state_t;

    state_t state_curr;

    always_comb begin 
        current_grant_found = 0;
        current_grant = 0;
        if(reset) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < ADDR_DEPTH; j++) begin
                    grant_mask_per_bank[i][j] = 0;
                    current_grant = 0;
                    bank_grant[i] = 0;
                    thread_to_read[i] = 0;
                    addr_bank[i]  = 0; //bank address
                    addr_depth[i] = 0; //depth address 
                end
            end            
        end
        else if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                addr_bank[i]  = addr[i][3 : 0]; //bank address
                addr_depth[i] = addr[i][7 : 4]; //depth address 
            end
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < ADDR_DEPTH; j++) begin
                    for (integer k = 0; k < NUMBER_OF_THREADS; k++) begin
                        if(addr_bank[k] == i) begin
                            grant_mask_per_bank[i][j][k] = addr_depth[k] == j;
                        end
                    end
                end       
            end
        end
        else begin
        current_grant = 0;
        for (integer i = 0; i < BANKS; i++) begin
            current_grant_found = 0;
            for (integer j = 0; j < ADDR_DEPTH; j++) begin
                if(SERVE[i][j] == 2'b01 && VALID[i][j] && !current_grant_found) begin
                    for (integer k = 0; k < NUMBER_OF_THREADS; k++) begin
                        if((grant_mask_per_bank[i][j][k] && !current_grant_found) && (grant_left || !grant_left)) begin
                            thread_to_read[i] = k;  
                            current_grant[k] = current_grant[k] | grant_mask_per_bank[i][j][k];
                            grant_mask_per_bank[i][j][k] = 0;
                            current_grant_found = 1;
                        end 
                    end
                    bank_grant[i] = 1'b1;
                end
            end
        end
        end
        any_pending = 0;
        for (integer i = 0; i < BANKS; i++) begin
            for (integer j = 0; j < ADDR_DEPTH; j++) begin
                any_pending = any_pending | |grant_mask_per_bank[i][j] | VALID[i][j];
            end
        end
        stall = any_pending;
        for (integer i = 0; i < BANKS; i++) begin
            for (integer j = 0; j < ADDR_DEPTH; j++) begin
                if(!stall) begin
                    bank_grant[i] = 0;
                    thread_to_read[i] = 0;
                end
            end
        end
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < ADDR_DEPTH; j++) begin
                    VALID[i][j] <= 0;
                    SERVE[i][j] <= 0;
                    grant_left <= 0;
                    state_curr <= FIRST;
                    stall_cycles <= 0;
                end
            end
        end
        else if(mem_req) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < BANKS; j++) begin
                    SERVE[i][j] <= |grant_mask_per_bank[i][j] ? 01 : 10;
                    VALID[i][j] <= |grant_mask_per_bank[i][j] ? 1 : 0;
                end
            end            
        end
        else begin
            for (integer i = 0; i < BANKS; i++) begin
                valid_found = 0;
                for (integer j = 0; j < ADDR_DEPTH; j++) begin
                    if(SERVE[i][j] == 2'b01 && !valid_found && |grant_mask_per_bank[i][j] == 0) begin
                        SERVE[i][j] <= 2'b10;
                        VALID[i][j] <= 0;
                        valid_found = 1;
                        grant_left <= 0;
                    end
                    else if (|grant_mask_per_bank[i][j] == 1) begin
                        //use a state machine to keep always_comb running when grants are still reamining
                        //when ideally it couldve been broadcasted 
                        case (state_curr)
                            FIRST: begin
                                grant_left <= 0;
                                state_curr <= SECOND;
                            end
                            SECOND: begin
                                grant_left <= 1;
                                state_curr <= FIRST;
                            end 
                            default: state_curr <= FIRST;
                        endcase                 
                    end
                end
            end
        end
        if(stall) begin
            stall_cycles <= stall_cycles + 1;
        end
        if(!stall) begin
            for (integer i = 0; i < BANKS; i++) begin
                for (integer j = 0; j < ADDR_DEPTH; j++) begin
                    SERVE[i][j] <= 0;
                end
            end
            stall_cycles <= 0;
        end
    end

    genvar i;
    generate
        for (i = 0; i < BANKS; i++) begin   
            memory_bank mem_bank (
                .bank_en(bank_grant[i]),
                .clk(clk),
                .reset(reset),
                .mem_write(mem_write),
                .addr_depth(addr_depth[thread_to_read[i]]),
                .data_in(data_in[thread_to_read[i]]),
                .data_out(read_data[i]) 
            );
        end
    endgenerate

    always_comb begin
        for (integer a = 0; a < NUMBER_OF_THREADS; a++) begin
            if(current_grant[a]) begin
                data_out[a] = read_data[addr_bank[a]];     
            end
        end    
    end

endmodule
