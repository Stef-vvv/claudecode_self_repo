module sync_fifo_flag_generator #(
    parameter WIDTH = 8             
)(
    input wire clk, reset, enable,          
    output wire flag            
);

    reg [WIDTH-1:0] count_r;   

    always @(negedge clk or posedge reset) begin
        if (reset) begin
            count_r <= {WIDTH{1'b0}};     
        end else if (flag) begin
            count_r <= count_r + 1'b1;   
        end
    end

    assign flag = (count_r != 0) | enable; 

endmodule
