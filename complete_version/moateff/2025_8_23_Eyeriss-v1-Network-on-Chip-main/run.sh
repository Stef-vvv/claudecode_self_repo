iverilog -o fifo -g2012 ./src/fifo_top.v ./src/fifo_mem.v ./src/fifo_rd_ctrl.v ./src/fifo_wr_ctrl.v
iverilog -o gin -g2012 ./src/gin_mcc.sv ./src/gin_xbus.sv ./src/gin.sv ./src/gin_fifo.sv ./src/fifo_top.v ./src/fifo_mem.v ./src/fifo_rd_ctrl.v ./src/fifo_wr_ctrl.v
iverilog -o gon -g2012 ./src/gon_mcc.sv ./src/gon_xbus.sv ./src/gon.sv ./src/gon_fifo.sv ./src/fifo_top.v ./src/fifo_mem.v ./src/fifo_rd_ctrl.v ./src/fifo_wr_ctrl.v
