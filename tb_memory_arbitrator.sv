module tb_memory_arbitrator;
    parameter BANKS      = 16;
    parameter DW         = 16;
    parameter NUMBER_OF_THREADS  = 16; //systolic grid size 
    parameter ADDR_DEPTH = 16;
    parameter NUMBER_OF_WARPS = 4;

    logic clk;
    logic reset; 
    logic matmul;
    logic mem_write;
    logic mem_req;
    logic request_type;
    logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]warp_id_from_ws;
    logic[ADDR_DEPTH - 1 : 0]              addr[0 : NUMBER_OF_THREADS - 1]; // receive te whole address ad decode it here 
    logic[DW - 1 : 0]                      data_in[0 : NUMBER_OF_THREADS - 1];
    logic[DW -  1 : 0]                     data_out[0 : NUMBER_OF_THREADS - 1];  
    logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]rf_to_access;
    logic [$clog2(NUMBER_OF_WARPS) - 1 : 0]warp_id_to_ws;  
    logic[NUMBER_OF_THREADS - 1 : 0]       active_mask;
    logic stall;

    arbitrator dut (.*);
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

    initial begin
        reset = 1;
        repeat(3)@(posedge clk);
        reset = 0; 
        active_mask = 16'hFFFF;

        //test 1 : write some data into the banks(cause conflicts too)
        @(posedge clk);
        for (integer i = 0; i < BANKS; i++) begin
            if(i != 1 && i != 3 && i != 2) begin
                addr[i] = i[15 : 0];
                data_in[i] = i+1;
            end
        end
        
        addr[1] = 16'h0021;
        data_in[1] = 16'h0001;
        addr[3] = 16'h0031;
        data_in[3] = 16'h0003;
        addr[2] = 16'h0041;
        data_in[2] = 16'h0002;
        mem_write = 1;
        @(posedge clk);
        mem_req = 1;
        repeat(2)@(posedge clk);
        mem_write = 1;
        mem_req = 0;
        repeat(4)@(posedge clk);
        mem_write = 0;

        //test 2: read the previously written data
        mem_req = 1;
        @(posedge clk);
        for (integer i = 0; i < BANKS; i++) begin
            if(i != 1 && i != 3 && i != 2) begin
                addr[i] = i[15 : 0];
            end
        end
        addr[1] = 16'h0031; //read by thread 1 written by thread 3
        addr[3] = 16'h0021; //read by thread 3 written by thread 1
        addr[2] = 16'h0041;
        @(posedge clk);
        mem_req = 0;
        repeat(3)@(posedge clk);

        //test 3: Now cause no conflicts but first write some data
        @(posedge clk);
        for (integer i = 0; i < BANKS; i++) begin
            addr[i] = i[15 : 0];
            data_in[i] = i*2+1;
        end 
        @(posedge clk);
        mem_write = 1;  
        mem_req = 1; 
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(3)@(posedge clk);
        mem_write = 0;
        mem_req = 0;
        @(posedge clk);

        //test 4: Now read that data
        mem_req = 1;
        for (integer i = 0; i < BANKS; i++) begin
            if(i != 2 && i != 4) begin
                addr[i] = i[15 : 0];
            end
        end    
        addr[2] = 16'h0004; //written by thread 4 read by thread 2
        addr[4] = 16'h0002; //written by thread 2 read by thread 4
        repeat(2)@(posedge clk);
        mem_req = 0;
        @(posedge clk);     

        //test 5: send all requests to bank 1
        for(integer i = 0; i < BANKS; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b1};
            data_in[i] = i+1;
        end   
        @(posedge clk);
        mem_req = 1;
        mem_write = 1;
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(17)@(posedge clk);
        mem_write = 0;


        //test 6 read that data
        mem_req  = 1;
        for (integer i = 0; i < BANKS; i++) begin
            addr[i] = {8'b0, i[3:0], 4'b1};  // same addresses
        end
        @(posedge clk);
        mem_req = 0;
        repeat(17) @(posedge clk);


        //test 7: cause conflicts on multiple banks
        for(integer i = 0; i < 4; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0001};
            data_in[i] = i+1;
        end 
        for(integer i = 4; i < 8; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0010};
            data_in[i] = i+1;
        end 
        for(integer i = 8; i < 12; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0011};
            data_in[i] = i+1;
        end
        for(integer i = 12; i < 16; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0100};
            data_in[i] = i+1;
        end 
        @(posedge clk);
        mem_req = 1;
        mem_write = 1;
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(6)@(posedge clk);
        mem_write = 0;    
        @(posedge clk);   

        //test 8: read this data
        for(integer i = 0; i < 4; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
        end 
        for(integer i = 4; i < 8; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0010}; //read bank 2
        end 
        for(integer i = 8; i < 12; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0011}; //read bank 3
        end
        for(integer i = 12; i < 16; i++) begin
            addr[i] = {8'b0, i[3 : 0], 4'b0100}; //read bank 4
        end 
        @(posedge clk);
        mem_req = 1;
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(8)@(posedge clk);

        //test 9: multiple broadcasts
        for(integer i = 0; i < 4; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
        end 
        for(integer i = 4; i < 8; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0010}; //read bank 2(read the same register)
        end 
        for(integer i = 8; i < 12; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0011}; //read bank 3(read the same register)
        end
        for(integer i = 12; i < 15; i++) begin
            if(i != 13)
            addr[i] = {8'b0, i[3 : 0], 4'b0100}; //read bank 4
        end 
            addr[15] = 16'h0003; //broadcast at  different locations
            addr[13] = 16'h0003;
        @(posedge clk);
        mem_req = 1;
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(6)@(posedge clk);

        //test 10: a broadcasting bank has a conflict too
        for(integer i = 0; i < 4; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0001}; //read bank 1(read the same register)
        end 
        for(integer i = 4; i < 8; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0010}; //read bank 2(read the same register)
        end 
        for(integer i = 8; i < 12; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0011}; //read bank 3(read the same register)
        end
        for(integer i = 12; i < 15; i++) begin
            addr[i] = {8'b0, 4'b0000, 4'b0100}; //read bank 4
        end 
            addr[15] = 16'h00E4; // conflict in bank 4(read register 14)
        @(posedge clk);
        mem_req = 1;
        repeat(2)@(posedge clk);
        mem_req = 0;
        repeat(20)@(posedge clk);

        
        $finish;
    end
endmodule
