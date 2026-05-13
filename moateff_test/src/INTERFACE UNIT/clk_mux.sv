module clk_mux (
    input wire 	link_clk,      
    input wire 	core_clk,
	input wire  enable,
    input wire 	Direct_Back_Path,        
    input wire 	reset,        
    output wire clk_out   
);

   
    reg link_r1, link_r2, core_r1, core_r2;
	
	wire D_2_Link, D_2_core;
	
	assign D_2_Link = (!core_r2) & (!Direct_Back_Path);
	assign D_2_core = (!link_r2) & (Direct_Back_Path);

    always @(negedge link_clk or posedge reset) begin  
        if (reset) begin
			link_r1 <= 0;
            link_r2 <= 0;
        end else begin
			link_r1 <= D_2_Link;
            link_r2 <= link_r1;
        end
    end

    always @(negedge core_clk or posedge reset) begin  
        if (reset) begin
			core_r1 <= 0;
            core_r2 <= 0;
        end else begin
			core_r1 <= D_2_core;
			core_r2 <= core_r1;
        end
    end


    wire gated_link_clk, gated_core_clk;
	
	assign gated_link_clk = link_clk & link_r2;
	assign gated_core_clk = core_clk & core_r2;
	
    assign clk_out = (enable) ? (gated_link_clk || gated_core_clk) : 0;
	
endmodule

// when using FPGA we will use BUFGMUX cell as an IP.