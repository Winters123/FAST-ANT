/////////////////////////////////////////////////////////////////
// NUDT.  All rights reserved.
//*************************************************************
//                     Basic Information
//*************************************************************
//Vendor: NUDT
//Xperis URL://www.xperis.com.cn
//FAST URL://www.fastswitch.org 
//Target Device: Xilinx
//Filename: pgm.v
//Version: 2.0
//Author : (Yang Xiangrui) FAST Group
//*************************************************************
//                     Module Description
//*************************************************************
// 1)store pkt sending from UA
// 2)generating pkts
//*************************************************************
//                     Revision List
//*************************************************************
//	rn1: 
//      date:  2018/09/25
//      modifier: 
//      description: 
///////////////////////////////////////////////////////////////// 

module pgm_rd #(
	parameter PLATFORM = "Xilinx",
	LMID = 8'd62, //self MID
	NMID = 8'd5  //next MID
)(
	input clk,
	input rst_n,

//receive data & phv from Previous module
	
    input [1023:0] in_rd_phv,
	input in_rd_phv_wr, 
	output out_rd_phv_alf,

	input [133:0] in_rd_data,
	input in_rd_data_wr,
	input in_rd_valid_wr,
	input in_rd_valid,
	output out_rd_alf,

//transport phv and data to pgm_rd
    output reg [1023:0] out_rd_phv,
	output reg out_rd_phv_wr,
	input in_rd_phv_alf,

	(*mark_debug="true"*)output reg [133:0] out_rd_data, 
	(*mark_debug="true"*)output reg out_rd_data_wr,
	output reg out_rd_valid,
	output reg out_rd_valid_wr,
	input in_rd_alf,

//signals from PGM_WR
	input pgm_bypass_flag,
	input pgm_sent_start_flag,

//opration with PGM_RAM
	output reg rd2ram_rd,
	output reg [6:0] rd2ram_addr,
	input [143:0] ram2rd_rdata,

//input cfg packet from DMA
    input [133:0] cin_rd_data,
	input cin_rd_data_wr,
	output cout_rd_ready,

//output configure pkt to next module
    output reg [133:0] cout_rd_data,
	output reg cout_rd_data_wr,
	input cin_rd_ready,
//input sent_time_reg from pgm_wr
	input [63:0] in_rd_sent_time_reg,

	//timestamp
	input [31:0] timestamp2rd

);

//***************************************************
//        Intermediate variable Declaration
//****************************************************
//all wire/reg/parameter variable
//should be declare below here

reg soft_rst;
reg [31:0] sent_rate_cnt;
reg [31:0] sent_rate_reg;
reg [31:0] lat_pkt_cnt; //num of pkt between Probes
reg [31:0] lat_pkt_reg; //num of pkt between Probes
reg [63:0] sent_bit_cnt;
reg [63:0] sent_pkt_cnt;
reg lat_flag;

//record sent_time set by ANT sw.
reg [63:0] sent_time_reg;
reg [63:0] sent_time_cnt;

assign out_rd_alf = in_rd_alf;
assign out_rd_phv_alf = in_rd_phv_alf;
assign cout_rd_ready = cin_rd_ready;

(*mark_debug="true"*)reg [5:0] pgm_rd_state;

reg ctl_write_flag;  //if its a write signal that the destination is it self, we set it as 1, otherwise we set it as 0


/**add cycle counters for test pkts*/
reg [10:0] pkt_cycle_cnt;
//reg [31:0] sent_time_stamp;

/**regs and wires related to fifo*/
wire data_empty_flag; 
reg fifo_out_data_rd;
wire fifo_out_data_wr;
wire [133:0] fifo_out_data;
wire data_full_flag;

//***************************************************
//             Pkt Rd & Transmit
//***************************************************

localparam  IDLE_S = 6'd0,
			SENT_S = 6'd1,
			HAUNT1_S = 6'd3,
			HAUNT2_S = 6'd5,
			READ_S = 6'd2,
			WAIT_S = 6'd4,
			PROBE_S = 6'd8,
			INSERT_S = 6'd9,
			DISCARD_S = 6'd11,
			FIN_S = 6'd16;

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		// reset
		rd2ram_rd <= 1'b0;
		rd2ram_addr <= 7'b0;
		//outputs set to 0
		out_rd_data <= 134'b0;
		out_rd_data_wr <= 1'b0;
		out_rd_valid <= 1'b0;
		out_rd_valid_wr <= 1'b0;

		out_rd_phv <= 1024'b0;
		out_rd_phv_wr <= 1'b0;

		sent_rate_cnt <= 32'b0;

		lat_pkt_cnt <= 32'b0; //num of pkt between Probes
		//lat_pkt_reg <= 32'h0; //num of pkt between Probes
		sent_bit_cnt <= 64'b0;
		sent_pkt_cnt <= 64'b0;

		//lat_flag <= 1'b0;  //TODO add latency flag here
		sent_time_reg <= 64'b0;
		sent_time_cnt <= 64'b0;

		//this is only used for antDev v2
		pkt_cycle_cnt <= 11'b0;
		//sent_time_stamp <= 32'b0;

		pgm_rd_state <= IDLE_S;

		fifo_out_data_rd <= 1'b0;
	end

	else begin
		case(pgm_rd_state)
			IDLE_S: begin
				if(pgm_sent_start_flag == 1'b1) begin
					
					out_rd_data <= 134'b0;
					rd2ram_addr <= 7'b0;
					rd2ram_rd <= 1'b1;

					out_rd_data_wr <= 134'b0;
					out_rd_valid <= 1'b0;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					pgm_rd_state <= HAUNT1_S;
					sent_time_reg <= in_rd_sent_time_reg;

				end


				else if(data_empty_flag == 1'b0) begin
					fifo_out_data_rd<=1'b1;
					if(fifo_out_data[133:132] == 2'b01) begin
						out_rd_data <= 134'b0;
						out_rd_data_wr <= 1'b0;
						out_rd_valid <= 1'b0;
						out_rd_valid_wr <= 1'b0;

						pgm_rd_state <= SENT_S;
					end

					else begin
						fifo_out_data_rd <= 1'b1;
						pgm_rd_state <= DISCARD_S;
					end
				end

				else begin
					rd2ram_rd <= 1'b0;
					rd2ram_addr <= 7'b0;
					//outputs set to 0
					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;

					sent_rate_cnt <= 32'b0;
					//sent_rate_reg <= 32'b0;
					lat_pkt_cnt <= 32'b0; //num of pkt between Probes
					//lat_pkt_reg <= 32'b0; //num of pkt between Probes
					sent_bit_cnt <= 64'b0;
					sent_pkt_cnt <= 64'b0;

					sent_time_cnt <= 64'b0;

					fifo_out_data_rd <= 1'b0;
					//only used in antDev v2
					pkt_cycle_cnt <= 11'b0;
					//sent_time_stamp <= 32'b0;

					pgm_rd_state <= IDLE_S;
				end
			end

			SENT_S: begin

				if(out_rd_data[133:132]==2'b10 && out_rd_data_wr == 1'b1)begin
					out_rd_data_wr <= 1'b0;
					out_rd_data <= 134'b0;
					out_rd_valid <= 1'b1;
					out_rd_valid_wr <= 1'b1;
					pgm_rd_state <= IDLE_S;
				end

				else if(fifo_out_data_wr==1'b1 && fifo_out_data[133:132]==2'b01) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;
					fifo_out_data_rd <= 1'b1;
					out_rd_phv <= 1024'b1;
					out_rd_phv_wr <= 1'b1;
					pgm_rd_state <= SENT_S;
				end

				else if(fifo_out_data_wr==1'b1 && fifo_out_data[133:132]==2'b11) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;
					fifo_out_data_rd <= 1'b1;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					pgm_rd_state <= SENT_S;
				end

				else if(fifo_out_data_wr==1'b1 && fifo_out_data[133:132]==2'b10) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;

					fifo_out_data_rd <= 1'b0;
				end

				else begin
					
					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_valid_wr <=1'b0;
					fifo_out_data_rd <= 1'b1;
					
					pgm_rd_state <= DISCARD_S;
				end
			end

			HAUNT1_S: begin
				rd2ram_rd <= 1'b1;
				rd2ram_addr <= 7'b1;
				sent_time_cnt <= sent_time_cnt + 1'b1;
				pgm_rd_state <= HAUNT2_S;
			end

			HAUNT2_S: begin
				rd2ram_rd <= 1'b1;
				rd2ram_addr <= 7'd2;
				sent_time_cnt <= sent_time_cnt + 1'b1;

				pgm_rd_state <= READ_S;
			end

			READ_S: begin
				//need to increment sent_rate_cnt as needed
				sent_time_cnt <= sent_time_cnt + 1'b1;

				//only needed in antDev v2
				//sent_time_stamp <= sent_time_stamp + 32'b1;

				if(ram2rd_rdata[133:132] == 2'b11) begin

					rd2ram_rd <= 1'b1;
					rd2ram_addr <= rd2ram_addr + 1'b1;
					sent_bit_cnt <= sent_bit_cnt + 64'd16;

					//only used in antDev v2
					pkt_cycle_cnt <= pkt_cycle_cnt + 11'b1;

					pgm_rd_state <= READ_S;

					//only used in antDev v2
					if (pkt_cycle_cnt == 11'd4) begin
						// only needed in antDev v2
						out_rd_data <= {ram2rd_rdata[133:128], sent_pkt_cnt, timestamp2rd, 32'hffffffff};
						out_rd_data_wr <= 1'b1;
						out_rd_valid <= 1'b0;
						out_rd_phv <= 1024'b0;
						out_rd_phv_wr <= 1'b0;
						out_rd_valid_wr <= 1'b0;
					end
					else begin
						out_rd_data <= ram2rd_rdata[133:0];
						out_rd_data_wr <= 1'b1;
						out_rd_valid <= 1'b0;
						out_rd_phv <= 1024'b0;
						out_rd_phv_wr <= 1'b0;
						out_rd_valid_wr <= 1'b0;
					end
				end

				else if(ram2rd_rdata[133:132] == 2'b10) begin
					rd2ram_rd <= 1'b0;
					rd2ram_addr <= 7'b0;

					if(pkt_cycle_cnt == 11'd4) begin
						out_rd_data <= {ram2rd_rdata[133:128], sent_pkt_cnt, timestamp2rd, 32'hffffffff};
					end

					else begin
						out_rd_data <= ram2rd_rdata[133:0];
					end
					
					out_rd_data_wr <= 1'b1;
					
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;

					/**How we use valid signal is wrong here*/
					out_rd_valid_wr <= 1'b1;
					out_rd_valid <= 1'b1;

					sent_bit_cnt <= sent_bit_cnt + ram2rd_rdata[131:128];
					sent_pkt_cnt <= sent_pkt_cnt + 1'b1;

					if(sent_time_cnt >= sent_time_reg) begin
						pgm_rd_state <= FIN_S;
					end

					else begin
						pgm_rd_state <= WAIT_S;
					end
				end

				else if(ram2rd_rdata[133:132] == 2'b01) begin
					rd2ram_rd <= 1'b1;
					rd2ram_addr <= rd2ram_addr + 7'b1;

					out_rd_data <= ram2rd_rdata[133:0];
					out_rd_data_wr <= 1'b1;
					out_rd_valid <= 1'b0;
					out_rd_phv <= 1024'b1;
					out_rd_phv_wr <= 1'b1;
					out_rd_valid_wr <= 1'b0;

					pgm_rd_state <= READ_S;

					sent_bit_cnt <= sent_bit_cnt + 64'd16;

					//only used in andDev v2
					pkt_cycle_cnt <= 11'b0;

				end
            
            end

			WAIT_S: begin

				sent_time_cnt <= sent_time_cnt + 1'b1;

				//the priority of data in the fifo is higher than generating pkt.
				if(data_empty_flag == 1'b0) begin
					//send pkt from fifo
					sent_rate_cnt <= sent_rate_cnt + 1'b1;

					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					fifo_out_data_rd <= 1'b1;
					pgm_rd_state <= INSERT_S;
				end

				else begin

					fifo_out_data_rd <= 1'b0;

					if(sent_rate_cnt >= sent_rate_reg) begin
						rd2ram_rd <= 1'b1;
						rd2ram_addr <= 7'b0000000;
						out_rd_data <= 134'b0;
						out_rd_data_wr <= 1'b0;
						out_rd_valid <= 1'b0;
						out_rd_phv_wr <= 1'b0;
						out_rd_phv <= 1024'b0;
						out_rd_valid_wr <= 1'b0;

						sent_rate_cnt <= 32'b0;
						pgm_rd_state <= HAUNT1_S;
					end

					else begin
						sent_rate_cnt <= sent_rate_cnt + 1'b1;

						out_rd_data <= 134'b0;
						out_rd_data_wr <= 1'b0;
						out_rd_valid <= 1'b0;
						out_rd_phv <= 1024'b0;
						out_rd_phv_wr <= 1'b0;
						out_rd_valid_wr <= 1'b0;

						if(sent_time_cnt >= sent_time_reg) begin
							pgm_rd_state <= FIN_S;
						end
					end
				end



			end

			INSERT_S: begin
				sent_time_cnt <= sent_time_cnt + 1'b1;
				sent_rate_cnt <= sent_rate_cnt + 1'b1;

				if (out_rd_data[133:132] == 2'b10 && out_rd_data_wr==1'b1) begin
					out_rd_data_wr <= 1'b0;
					out_rd_data <= 134'b0;
					out_rd_valid <= 1'b1;
					out_rd_valid_wr <= 1'b1;
					pgm_rd_state <= WAIT_S;
				end
				
				else if(fifo_out_data[133:132]==2'b01 && fifo_out_data_rd==1'b1) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;
					out_rd_phv <= 1024'b1;
					out_rd_phv_wr <= 1'b1;
				end

				else if(fifo_out_data[133:132]==2'b11 && fifo_out_data_rd==1'b1) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
				end

				else if(fifo_out_data[133:132]==2'b10 && fifo_out_data_rd==1'b1) begin
					out_rd_data <= fifo_out_data;
					out_rd_data_wr <= fifo_out_data_wr;
					fifo_out_data_rd <= 1'b0;
				end


				else begin
					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					fifo_out_data_rd <= 1'b1;
					pgm_rd_state <= DISCARD_S;
				end
			end

			FIN_S: begin
				if(soft_rst == 1'b1) begin
					pgm_rd_state <= IDLE_S;
				end	
				else begin
					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					pgm_rd_state <= FIN_S;
				end
			end

			DISCARD_S: begin
				if(fifo_out_data[133:132] != 2'b10 && fifo_out_data_wr == 1'b1) begin

					fifo_out_data_rd <= 1'b1;
					//outputs set to 0
					out_rd_data <= 134'b0;
					out_rd_data_wr <= 1'b0;
					out_rd_valid <= 1'b0;
					out_rd_valid_wr <= 1'b0;

					out_rd_phv <= 1024'b0;
					out_rd_phv_wr <= 1'b0;
				end 

				else begin
					fifo_out_data_rd <= 1'b0;
					pgm_rd_state <= IDLE_S;
				end
			end

		endcase
	end
end







//***************************************************
//                  Other IP Instance
//***************************************************
//likely fifo/ram/async block.... 
//should be instantiated below here

fifo_135_512 pgm_rd_data_fifo
(
	.clk(clk),
	.srst(!rst_n),
	.din({in_rd_data_wr,in_rd_data}),
	.wr_en(in_rd_data_wr),
	.rd_en(fifo_out_data_rd),
	.dout({fifo_out_data_wr,fifo_out_data}),
	.full(data_full_flag),
	.almost_full(),
	.empty(data_empty_flag),
	.data_count()
);


//***************************************************
//          Operation of User Defined Regs
//***************************************************


always @(posedge clk) begin
	//1st cycle of control packet 
	if(cin_rd_data[133:132] == 2'b01 && cin_rd_data_wr == 1'b1) begin
		if ((cin_rd_data[103:96]== 8'd62) && (cin_rd_data[126:124] == 3'b010) && (rst_n==1'b1)) begin
			//write signal from SW
			
			case(cin_rd_data[95:64])

				32'h00000000: begin
					soft_rst <= cin_rd_data[0];
				end
				
				32'h00010001: begin
					 sent_rate_reg <= cin_rd_data[31:0];
				end
				32'h00010002: begin
					 lat_pkt_reg <= cin_rd_data[31:0];
				
				end
				32'h00010010: begin
					lat_flag <= cin_rd_data[0];
				end
				

			endcase
			ctl_write_flag <= 1'b1;
			cout_rd_data <= 134'b0;
			cout_rd_data_wr <= 1'b0;
			
		end

		else if(cin_rd_data[103:96]== 8'd62 && cin_rd_data[126:124] == 3'b001) begin
			//read signal from SW
			ctl_write_flag <= 1'b0;
			case(cin_rd_data[95:64])
				32'h00000000: begin
					//cin_rd_data[0] <= soft_rst;
					cout_rd_data <= {cin_rd_data[133:128], 1'b1, 3'b011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:1], soft_rst};
				end
				32'h00000001: begin
					//cin_rd_data[31:0] <= sent_rate_cnt;
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_rate_cnt};
				end
				32'h00010001: begin
					//cin_rd_data[31:0] <= sent_rate_reg;
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_rate_reg};
				end
				32'h00000002: begin
					//cin_rd_data[31:0] <= lat_pkt_cnt;
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], lat_pkt_cnt};
				end
				32'h00010002: begin
					//cin_rd_data[31:0] <= lat_pkt_reg;
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], lat_pkt_reg};
				end
				32'h00000003: begin
					//cin_rd_data[31:0] <= sent_bit_cnt[31:0];
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_bit_cnt[31:0]};
				end
				32'h00000004: begin
					//cin_rd_data[31:0] <= sent_bit_cnt[63:32];
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_bit_cnt[63:32]};
				end
				32'h00000005: begin
					//cin_rd_data[31:0] <= sent_pkt_cnt[31:0];
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_pkt_cnt[31:0]};
				end
				32'h00000006: begin
					//cin_rd_data[31:0] <= sent_pkt_cnt[63:32];
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], sent_pkt_cnt[63:32]};
				end
				32'h00010010: begin
					cout_rd_data <= {cin_rd_data[133:128], 1'b1, 3'b011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:1], lat_flag};
				end
				32'h11111111: begin
					cout_rd_data <= {cin_rd_data[133:128], 1'b1, 3'b011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:6], pgm_rd_state};
				end
				default: begin
					cout_rd_data <= {cin_rd_data[133:128], 4'b1011, cin_rd_data[123:112], cin_rd_data[103:96], cin_rd_data[111:104], cin_rd_data[95:32], 32'hffffffff};
				end

			endcase
			cout_rd_data_wr <= cin_rd_data_wr;
		end

		else begin
			ctl_write_flag <= 1'b0;
			cout_rd_data <= cin_rd_data;
			cout_rd_data_wr <= cin_rd_data_wr;
		end
	end
	//2nd cycle of control packet
	else if(cin_rd_data[133:132] == 2'b10 && cin_rd_data_wr == 1'b1) begin
		if (ctl_write_flag == 1'b1) begin
			cout_rd_data_wr <= 1'b0;
			cout_rd_data <= 134'b0;
			ctl_write_flag <= 1'b0;
		end

		else begin
			
			cout_rd_data_wr <= cin_rd_data_wr;
			cout_rd_data <= cin_rd_data;
			
		end

	end

	else begin
		cout_rd_data_wr <= cin_rd_data_wr;
		cout_rd_data <= cin_rd_data;
	end


end



endmodule