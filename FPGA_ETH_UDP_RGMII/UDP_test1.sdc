# 1. 定义你的主系统时钟 (假设 50MHz)
#    (如果你的板子晶振不是50MHz, 请修改 20.000)
create_clock -name "sys_clk" -period 20.000 [get_ports {clk}]

# 2. 定义从PHY芯片传来的 MII 时钟 (100Mbps 模式是 25MHz)
create_clock -name "mii_rx_clk" -period 40.000 [get_ports {enet0_rx_clk}]
create_clock -name "mii_tx_clk" -period 40.000 [get_ports {enet0_tx_clk}]

# 3. 【最关键的一步】
#    告诉编译器：这三组时钟是“异步”的（来自不同晶振），
#    不要试图在它们之间做时序分析，要老老实实地建立“海关”(CDC)。
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {mii_rx_clk}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {mii_tx_clk}]
set_clock_groups -asynchronous -group [get_clocks {mii_rx_clk}] -group [get_clocks {mii_tx_clk}]

# 4. 告诉编译器 MDIO 是一个慢速总线，不用管它的时序
set_false_path -from [get_ports {enet0_mdc}] -to [get_ports {enet0_mdio}]
set_false_path -from [get_ports {enet0_mdio}] -to [get_ports {enet0_mdc}]