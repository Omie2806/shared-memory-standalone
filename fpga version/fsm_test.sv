module tb_arbitrator_fsm #(
    parameter NUMBER_OF_THREADS = 16,
    parameter NUMBER_OF_WARPS = 16,
    parameter BANKS = 16,
    parameter ADDR_DEPTH = 16,
    parameter DW = 16 
) (
    input logic clk,
    input logic reset,
    input logic[3 : 0] test_number,
    output logic done,
    output logic error
);

typedef enum logic [2 : 0] {
    IDLE    = 3'b000,
    WRITE   = 3'b001,
    READ    = 3'b010,
    WAIT    = 3'b011,
    MEM_REQ = 3'b100,
    DONE    = 3'b101
} state_t;

state_t state_curr;  

logic mem_write;
logic mem_req;
logic matmul;
logic request_type;
logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]warp_id_from_ws;
logic[ADDR_DEPTH - 1 : 0]              addr[0 : NUMBER_OF_THREADS - 1]; // receive te whole address ad decode it here 
logic[DW - 1 : 0]                      data_in[0 : NUMBER_OF_THREADS - 1];
logic[DW -  1 : 0]                     data_out[0 : NUMBER_OF_THREADS - 1];
logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]rf_to_access;
logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]warp_id_to_ws;
logic[NUMBER_OF_THREADS - 1 : 0]       active_mask;
logic stall;

logic[7 : 0] wait_counter;
logic[1 : 0] mem_req_wait;

arbitrator dut (
    .clk(clk),
    .reset(reset),
    .mem_write(mem_write),
    .mem_req(mem_req),
    .matmul(matmul),
    .request_type(request_type),
    .warp_id_from_ws(warp_id_from_ws),
    .addr(addr),
    .data_in(data_in),
    .data_out(data_out),
    .rf_to_access(rf_to_access),
    .warp_id_to_ws(warp_id_to_ws),
    .active_mask(active_mask),
    .stall(stall)
);

always_comb begin 
    case (state_curr)
        IDLE: begin
            mem_req = 1;
        end
        MEM_REQ: begin
            if(mem_req_wait == 0) begin
                mem_req = 0;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    if(reset) begin
        active_mask = 16'hFFFF;
        mem_write <= 0;
        mem_req_wait <= 0;
        wait_counter <= 0;
        for (integer i = 0; i < NUMBER_OF_THREADS; i++) begin
            addr[i] <= 0;
            data_in[i] <= 0;
        end
    end
    else begin
        case (state_curr)
            IDLE: begin case (test_number)
                4'b0000: begin
                    for (integer i = 0; i < NUMBER_OF_THREADS; i++) begin
                        if(i != 1 && i != 3 && i != 2) begin
                            addr[i] <= i[15 : 0];
                            data_in[i] <= i+1;
                        end
                        addr[1] <= 16'h0021;
                        data_in[1] <= 16'h0001;
                        addr[3] <= 16'h0031;
                        data_in[3] <= 16'h0003;
                        addr[2] <= 16'h0041;
                        data_in[2] <= 16'h0002;                
                    end
                    mem_write <= 1;
                    // mem_req = 1;
                    mem_req_wait <= 2;
                    state_curr <= MEM_REQ;
                    wait_counter <= 4;
                end
                4'b0001: begin
                    // mem_req = 1;
                    for (integer i = 0; i < BANKS; i++) begin
                        if(i != 1 && i != 3 && i != 2) begin
                            addr[i] <= i[15 : 0];
                        end
                    end
                    addr[1] <= 16'h0031; //read by thread 1 written by thread 3
                    addr[3] <= 16'h0021; //read by thread 3 written by thread 1
                    addr[2] <= 16'h0041;
                    mem_req_wait <= 2;
                    state_curr <= MEM_REQ;
                    wait_counter <= 3;
                end
                4'b0010: begin
                    for (integer i = 0; i < BANKS; i++) begin
                        addr[i] <= i[15 : 0];
                        data_in[i] <= i*2+1;
                    end
                    // mem_req = 1;
                    mem_write <= 1;
                    state_curr <= MEM_REQ;
                    mem_req_wait <= 2;
                    wait_counter <= 3; 
                end
                4'b0011: begin
                    //mem_req = 1;
                    for (integer i = 0; i < BANKS; i++) begin
                        if(i != 2 && i != 4) begin
                            addr[i] <= i[15 : 0];
                        end
                    end    
                    addr[2] <= 16'h0004; //written by thread 4 read by thread 2
                    addr[4] <= 16'h0002; //written by thread 2 read by thread 4
                    state_curr <= MEM_REQ;
                    mem_req_wait <= 2;
                    wait_counter <= 3;
                end
                4'b0100: begin
                    //mem_req = 1;
                    mem_write <= 1;
                    mem_req_wait <= 2;
                    wait_counter <= 17;
                    state_curr <= MEM_REQ;
                    for(integer i = 0; i < BANKS; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b1};
                        data_in[i] <= i+1;
                    end 
                end
                4'b0101: begin
                    //mem_req = 1;
                    mem_req_wait <= 2;
                    wait_counter <= 17;
                    state_curr <= MEM_REQ;
                    for (integer i = 0; i < BANKS; i++) begin
                        addr[i] <= {8'b0, i[3:0], 4'b1};  // same addresses
                    end
                end
                4'b0110: begin
                    //mem_req = 1;
                    mem_write <= 1;
                    mem_req_wait <= 2;
                    wait_counter <= 6;
                    state_curr <= MEM_REQ;
                    for(integer i = 0; i < 4; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0001};
                        data_in[i] <= i+1;
                    end 
                    for(integer i = 4; i < 8; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0010};
                        data_in[i] <= i+1;
                    end 
                    for(integer i = 8; i < 12; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0011};
                        data_in[i] <= i+1;
                    end
                    for(integer i = 12; i < 16; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0100};
                        data_in[i] <= i+1;
                    end                    
                end
                4'b0111: begin
                    //mem_req = 1;
                    mem_req_wait <= 2;
                    wait_counter <= 6;
                    state_curr <= MEM_REQ;
                    for(integer i = 0; i < 4; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
                    end 
                    for(integer i = 4; i < 8; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0010}; //read bank 2
                    end 
                    for(integer i = 8; i < 12; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0011}; //read bank 3
                    end
                    for(integer i = 12; i < 16; i++) begin
                        addr[i] <= {8'b0, i[3 : 0], 4'b0100}; //read bank 4
                    end 
                end
                4'b1000: begin
                    //mem_req = 1;
                    mem_req_wait <= 2;
                    wait_counter <= 6;
                    state_curr <= MEM_REQ;
                    for(integer i = 0; i < 4; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
                    end 
                    for(integer i = 4; i < 8; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0010}; //read bank 2(read the same register)
                    end 
                    for(integer i = 8; i < 12; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0011}; //read bank 3(read the same register)
                    end
                    for(integer i = 12; i < 15; i++) begin
                        if(i != 13)
                            addr[i] <= {8'b0, i[3 : 0], 4'b0100}; //read bank 4
                    end 
                    addr[15] <= 16'h0003; //broadcast at  different locations
                    addr[13] <= 16'h0003;                    
                end
                4'b1001: begin
                    //mem_req = 1;
                    mem_req_wait <= 2;
                    wait_counter <= 6;
                    state_curr <= MEM_REQ;
                    for(integer i = 0; i < 4; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
                    end 
                    for(integer i = 4; i < 8; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0010}; //read bank 2(read the same register)
                    end 
                    for(integer i = 8; i < 12; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0011}; //read bank 3(read the same register)
                    end
                    for(integer i = 12; i < 15; i++) begin
                        addr[i] <= {8'b0, 4'b0000, 4'b0100}; //read bank 4
                    end 
                    addr[15] <= 16'h00E4; // conflict in bank 4(read register 14)                    
                end 
            endcase
            end
            MEM_REQ: begin
                if(mem_req_wait == 0) begin
                    if(mem_write) begin
                        state_curr <= WRITE;
                        //mem_req = 0;
                    end
                    else begin
                        state_curr <= READ;
                        //mem_req = 0;
                    end
                end
                else begin
                    mem_req_wait <= mem_req_wait - 1;
                end
            end
            WRITE: begin
                if(wait_counter == 0) begin
                    state_curr <= DONE;
                    mem_write <= 0;
                end
                else begin
                    wait_counter <= wait_counter - 1;
                end
            end
            READ: begin
                if(wait_counter == 0) begin
                    state_curr <= DONE;
                end 
                else begin
                    wait_counter <= wait_counter - 1;
                end
            end
            DONE: begin
                state_curr <= IDLE;
                done <= 1;
                wait_counter <= 0;
                mem_req_wait <= 0;
                mem_write <= 0;
            end
            default: state_curr <= IDLE;
        endcase
    end
end
endmodule
