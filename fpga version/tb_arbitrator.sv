module tb_fsm_test;
logic clk;
logic reset;
logic[3 : 0] test_number;
logic mem_req_out;
logic mem_write_out;
logic data_in_out;
logic done;
logic error;

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

tb_arbitrator_fsm fsm_inst (.*);

initial begin
    reset = 1;
    repeat(2)@(posedge clk);
    reset = 0;
    test_number = 4'b0000;
   repeat(10)@(posedge clk);
   test_number = 4'b0001;
   repeat(10)@(posedge clk);
   test_number = 4'b0010;
   repeat(9)@(posedge clk);
   test_number = 4'b0011;
   repeat(9)@(posedge clk);
   test_number = 4'b0100;
   repeat(22)@(posedge clk);   
   test_number = 4'b0101;
   repeat(22)@(posedge clk);  
   test_number = 4'b0110;
   repeat(12)@(posedge clk);
   test_number = 4'b0111;
   repeat(12)@(posedge clk);
   test_number = 4'b1000;
   repeat(12)@(posedge clk);
   test_number = 4'b1001;
   repeat(12)@(posedge clk);
   $finish; 
end


endmodule
