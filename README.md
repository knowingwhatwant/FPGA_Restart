# FPGA_Restart







## 一些技巧知识点

- 单脉冲指示信号

```verilog
// 单脉冲发送指示，只存在一个时钟周期
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            send_go <= 0;
        end else if(cnt == 1)begin     
            send_go <= 1; // Enable sending every 10ms
        end else begin
            send_go <= 0; 
        end
    end
```

应用场景：



- reg和wire的使用



