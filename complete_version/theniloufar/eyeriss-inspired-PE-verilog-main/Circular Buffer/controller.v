module controller(input clk, rst, ren, valid, wen, ready, output reg cntR, cntW, write_en);
    parameter [2:0] IDLE = 0, READ = 1, WRITE = 2, READ_WRITE = 3;
    reg [2:0] ns = 3'b0, ps = 3'b0;

    always @(posedge clk, negedge clk, posedge rst) begin
        if (rst) begin
            ps <= 3'b0;
            ns <= 3'b0;
        end
        else    
            ps <= ns;
    end

    always @(ps, ren, valid, wen, ready) begin
		case (ps)
			IDLE: begin 
                    ns <= (ren && valid && ~(wen && ready)) ? READ :
                    (~(ren && valid) && wen && ready) ? WRITE :
                    (ren && valid && wen && ready) ? READ_WRITE : IDLE; 
                end
            READ: ns = IDLE;
            WRITE: ns = IDLE;
            READ_WRITE: ns = IDLE;
            default: ns = IDLE;
		endcase
	end

    always @(ps) begin
		{cntR, cntW, write_en} = 3'b0;
		case (ps)
			IDLE:;
            READ: cntR = 1'b1;
            WRITE: {cntW, write_en} = 2'b11;
            READ_WRITE: {cntR, cntW, write_en} = 3'b111;
			default:;
		endcase
	end
endmodule