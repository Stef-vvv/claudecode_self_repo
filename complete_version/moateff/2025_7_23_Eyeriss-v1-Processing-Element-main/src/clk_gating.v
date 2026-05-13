module clk_gating (
    input  enable,
    input  clk,
    output gated_clk
);

    // Internal latch for clock enable control
    reg latch_en;
    
    // Level-sensitive latch
    always @(clk or enable) begin
        if (!clk) begin  // Transparent when CLK is low
            latch_en <= enable;
        end
    end
    
    // Clock gating logic using AND gate
    assign gated_clk = clk & latch_en;

endmodule
