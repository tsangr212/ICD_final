module SW #(parameter WIDTH_SCORE = 8, parameter WIDTH_POS_REF = 7, parameter WIDTH_POS_QUERY = 6)
       (
           input           clk,
           input           reset,
           input           valid,
           input [1:0]     data_ref,
           input [1:0]     data_query,
           output          finish,
           output [WIDTH_SCORE - 1:0]   max,
           output [WIDTH_POS_REF - 1:0]   pos_ref,
           output [WIDTH_POS_QUERY - 1:0]   pos_query
       );

//------------------------------------------------------------------
// parameter
//------------------------------------------------------------------
parameter IDLE = 3'd0;
parameter CAL1 = 3'd1;                  // CAL1 ~ H[1][64] is computed
parameter CAL2 = 3'd2;
parameter CAL3 = 3'd3;
parameter OUT = 3'd4;
parameter signed gopen = 8'hFE; /////////////gopen is negative = -2
parameter signed gextend = 8'hFF;///////////gextend = -1
parameter signed match = 8'h02;
parameter signed mismatch = 8'hFF;
parameter signed zero = 8'h00;
parameter num_q = 7'd47;
parameter num_h0 = 7'd48;
//parameter num_2q = 7'd95;
parameter num_r = 7'd63;
parameter num_s = 7'd15;   // s for size
parameter num_2s = 7'd31;
integer i;

//------------------------------------------------------------------
// reg & wire
//------------------------------------------------------------------
reg [2:0] state, state_n;
reg [6:0] count, count_n;
reg [1:0] row, row_n;
reg [WIDTH_SCORE-1:0] maxi, maxi_n;
reg [WIDTH_POS_REF-1:0] refi, refi_n;
reg [WIDTH_POS_QUERY-1:0] queryi, queryi_n;


reg [1:0] ref [0:num_r];
reg [1:0] ref_n [0:num_r];
reg [1:0] query [0:num_q];
reg [1:0] query_n [0:num_q];

reg signed [7:0] S [0:num_s];
reg signed [7:0] S_n [0:num_s];
reg [1:0] S_ref [0:num_s];
reg [1:0] S_query [0:num_s];
reg [1:0] S_query_n [0:num_s];

reg signed [WIDTH_SCORE-1:0] I [0:num_s];
reg signed [WIDTH_SCORE-1:0] I_n [0:num_s];
reg signed [WIDTH_SCORE-1:0] I0 [0:num_q];
reg signed [WIDTH_SCORE-1:0] D [0:num_s];
reg signed [WIDTH_SCORE-1:0] D_n [0:num_s];
reg signed [WIDTH_SCORE-1:0] H0 [0:num_h0];
reg signed [WIDTH_SCORE-1:0] H [0:num_2s];
reg signed [WIDTH_SCORE-1:0] H_n [0:num_2s];


reg signed [WIDTH_SCORE-1:0] max_h;
reg [WIDTH_POS_QUERY-1:0] max_i;



//------------------------------------------------------------------
// submodule
//------------------------------------------------------------------

//------------------------------------------------------------------
// combinational part
//------------------------------------------------------------------

assign max = maxi;
assign pos_query = queryi;
assign pos_ref = refi;
assign finish = (state==OUT)? 1'd1 : 1'd0;

/* ------------------------------------------------------------------ */ // not revised
/*                         state_n, count_n                           */
/* ------------------------------------------------------------------ */
//total 64*3+15 cycles, CAL1 63, CAL2 64*2, CAL3 17(finish at 16, but need extra cycle for max_h cal)
always @(*)
begin
    case(state)
        IDLE:
        begin
            state_n = (valid==1)? CAL1 : IDLE;
            count_n = 7'd0;
            row_n = 2'd0;
        end

        CAL1:
        begin
            state_n = (count < num_r-1)? CAL1 : CAL2;    // go to CAL2 as soon as all data arrived(count 1 gets 3rd data)
            count_n = (count < num_r-1)? count+1 : 7'd0;
            row_n = (count < num_r-1)? row : row+1;
        end

        CAL2:
        begin
            state_n = (row < 2'd2 | count < num_r)? CAL2 : CAL3;
            count_n = (count < num_r)? count+1 : 7'd0;
            row_n = (count < num_r)? row : row+1;
        end

        CAL3:
        begin
            state_n = (count < num_s+1)? CAL3 : OUT;  // +1 for max_h cal
            count_n = count + 1;
            row_n = row;
        end
        default:
        begin
            state_n = IDLE;
            count_n = 7'd0;
            row_n = 2'd0;
        end
    endcase
end

/* ------------------------------------------------------------------ */
/*                          S_ref, S_query                            */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            S_query_n[0] = (valid==1)? data_query :2'd1;
            for(i=1;i<=num_s;i=i+1)
            begin
                S_query_n[i] = S_query[i];
            end
        end

        CAL1:
        begin
            S_query_n[0] = S_query[0];
            for(i=1;i<=num_s;i=i+1)
            begin
                S_query_n[i] = (count==i-1)? data_query : S_query[i];
            end
        end

        CAL2:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                S_query_n[i] = (count==i)? query[i+(num_s+1)*row] : S_query[i];
            end
        end

        CAL3:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                S_query_n[i] = (count==i)? 2'd1 : S_query[i];
            end
        end
        default:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                S_query_n[i] = S_query[i];
            end
        end
    endcase
end

/* ------------------------------------------------------------------ */
/*                                S_n                                 */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            for(i=1;i<=num_s;i=i+1)
            begin
                S_n[i] = S[i];
            end
            if(valid==1)
            begin
                S_n[0] = (data_query==data_ref)? match : mismatch;  // compute S_n[0] st IDLE state
            end
            else
            begin
                S_n[0] = S[0];
            end

        end

        CAL1:
        begin
            S_n[0] = (data_ref==S_query[0])? match : mismatch;
            for(i=1;i<=num_s;i=i+1)
            begin
                S_n[i] = (i-1==count)? ((data_query==S_ref[i-1])? match : mismatch) :
                    (S_ref[i-1]==S_query[i])? match : mismatch;
            end
        end

        CAL2:
        begin
            S_n[0] = (S_query_n[0]==ref[count])? match : mismatch;
            for(i=1;i<=num_s;i=i+1)
            begin
                S_n[i] = (S_query_n[i]==S_ref[i-1])? match : mismatch;
            end
        end
        CAL3:
        begin
            S_n[0] = mismatch;
            for(i=1;i<=num_s;i=i+1)
            begin
                S_n[i] = (S_query_n[i]==S_ref[i-1])? match : mismatch;
            end
        end
        default:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                S_n[i] = S[i];
            end
        end
    endcase
end

/* ------------------------------------------------------------------ */
/*                            ref_n, query_n                          */
/* ------------------------------------------------------------------ */
always @(*)
begin
    for(i=0;i<=num_q;i=i+1)
    begin
        query_n[i] = query[i];
    end

    for(i=0;i<=num_r;i=i+1)
    begin
        ref_n[i] = ref[i];
    end
    if(state==IDLE)
    begin
        ref_n[0] = (valid==1)? data_ref : ref[0];
        query_n[0] = (valid==1)? data_query : query[0];
    end
    else if(state==CAL1)
    begin
        if(count<num_q)
        begin
            query_n[count+1] = data_query;
        end
        ref_n[count+1] = data_ref;
    end
end
/* ------------------------------------------------------------------ */
/*                                H0                                 */
/* ------------------------------------------------------------------ */
/* ------------------------------------------------------------------ */
/*                                H_n                                 */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            for(i=0;i<=num_2s;i=i+1)
            begin
                H_n[i] = H[i];
            end
        end

        CAL1:
        begin
            H_n[0] = (D[0][7] == 0)? {(D[0] > S[0])? D[0] : S[0]} : {(S[0] > zero)? S[0] : zero};   // I[0] must be -2, MSB of D indicates if it < 0
            for(i=1;i<=num_s;i=i+1)
            begin
                if(I[i]>D[i])
                begin
                    if(H[i+num_s]+S[i]>zero)
                    begin
                        H_n[i] = (I[i]>H[i+num_s]+S[i])? I[i] : H[i+num_s]+S[i];
                    end
                    else
                    begin
                        H_n[i] = (I[i]>zero)? I[i] : zero;
                    end
                end
                else
                begin
                    if(H[i+num_s]+S[i]>zero)
                    begin
                        H_n[i] = (D[i]>H[i+num_s]+S[i])? D[i] : H[i+num_s]+S[i];
                    end
                    else
                    begin
                        H_n[i] = (D[i]>zero)? D[i] : zero;
                    end
                end
            end

            for(i=num_s+1;i<=num_2s;i=i+1)
            begin
                H_n[i] = H[i-num_s-1];
            end
        end

        CAL2, CAL3:
        begin
            if(I[0]>D[0])
            begin
                if(H0[num_h0]+S[0]>zero)
                begin
                    H_n[0] = (I[0]>H0[num_h0]+S[0])? I[0] : H0[num_h0]+S[0];
                end
                else
                begin
                    H_n[0] = (I[0]>zero)? I[0] : zero;
                end
            end
            else
            begin
                if(H0[num_h0]+S[0]>zero)
                begin
                    H_n[0] = (D[0]>H0[num_h0]+S[0])? D[0] : H0[num_h0]+S[0];
                end
                else
                begin
                    H_n[0] = (D[0]>zero)? D[0] : zero;
                end
            end
            for(i=1;i<=num_s;i=i+1)
            begin
                if(I[i]>D[i])
                begin
                    if(H[i+num_s]+S[i]>zero)
                    begin
                        H_n[i] = (I[i]>H[i+num_s]+S[i])? I[i] : H[i+num_s]+S[i];
                    end
                    else
                    begin
                        H_n[i] = (I[i]>zero)? I[i] : zero;
                    end
                end
                else
                begin
                    if(H[i+num_s]+S[i]>zero)
                    begin
                        H_n[i] = (D[i]>H[i+num_s]+S[i])? D[i] : H[i+num_s]+S[i];
                    end
                    else
                    begin
                        H_n[i] = (D[i]>zero)? D[i] : zero;
                    end
                end
            end

            for(i=num_s+1;i<=num_2s;i=i+1)
            begin
                H_n[i] = (i-(num_s+1)==count-1)? 8'd0 : H[i-num_s-1];
            end
        end

        default:
        begin
            for(i=0;i<=num_2s;i=i+1)
            begin
                H_n[i] = H[i];
            end
        end
    endcase
end
/* ------------------------------------------------------------------ */
/*                               I0_n                                 */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/*                                I_n                                 */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                I_n[i] = I[i];
            end
        end

        CAL1:
        begin
            I_n[0] = I[0];

            for(i=1;i<=num_s;i=i+1)
            begin
                I_n[i] = (count>=i-1)? {(H_n[i-1]+gopen > I[i-1]+gextend)? H_n[i-1]+gopen : I[i-1]+gextend} : I[i];
            end
        end

        CAL2, CAL3:
        begin
            I_n[0] = (H0[num_q-1]+gopen > I0[num_q]+gextend)? H0[num_q-1]+gopen : I0[num_q]+gextend;

            for(i=1;i<=num_s;i=i+1)
            begin
                I_n[i] = (H_n[i-1]+gopen > I[i-1]+gextend)? H_n[i-1]+gopen : I[i-1]+gextend;
            end
        end
        default:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                I_n[i] = I[i];
            end
        end
    endcase
end

/* ------------------------------------------------------------------ */
/*                                D_n                                 */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                D_n[i] = D[i];
            end
        end

        CAL1:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                D_n[i] = (count>=i-1)? {(H_n[i]+gopen > D[i]+gextend)? H_n[i]+gopen : D[i]+gextend} : D[i];
            end
        end

        CAL2, CAL3:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                D_n[i] = (i==count)? gopen :
                    (H_n[i]+gopen > D[i]+gextend)? H_n[i]+gopen : D[i]+gextend;
            end
        end
        default:
        begin
            for(i=0;i<=num_s;i=i+1)
            begin
                D_n[i] = D[i];
            end
        end
    endcase
end

/* ------------------------------------------------------------------ */
/*                maxi_n, queryi_n, refi_n, max_h, max_i              */
/* ------------------------------------------------------------------ */
always @(*)
begin
    case(state)
        IDLE:
        begin
            maxi_n = 8'd0;
            queryi_n = 6'd0;
            refi_n = 7'd0;
            max_h = 8'd0;
            max_i = 6'd0;
        end

        CAL1:
        begin
            max_i = num_s;
            max_h = H[num_s];
            for(i=0;i<num_s;i=i+1)
            begin // i=num_s need not be compared
                if(H[i] > max_h)
                begin
                    max_h = H[i];
                    max_i = i;
                end
            end

            if(max_h > $signed(maxi))
            begin
                maxi_n = max_h;
                //refi_n = count;
                refi_n = count-max_i;
                queryi_n = max_i+1;
            end
            else
            begin
                maxi_n = maxi;
                queryi_n = queryi;
                refi_n = refi;
            end
        end

        CAL2:
        begin
            max_i = num_s;
            max_h = H[num_s];
            for(i=0;i<num_s;i=i+1)
            begin
                if(H[i] > max_h)
                begin
                    max_h = H[i];
                    max_i = i;
                end
            end

            if(max_h > $signed(maxi))
            begin
                maxi_n = max_h;
                //refi_n = count;
                refi_n = ((count-max_i+num_r) > num_r+1)? count-max_i-1 : count-max_i+num_r;
                queryi_n = (count > max_i+1)? max_i+1+(1+num_s)*row :  max_i+1+(1+num_s)*(row-1);
            end
            else
            begin
                maxi_n = maxi;
                queryi_n = queryi;
                refi_n = refi;
            end
        end

        CAL3:
        begin                // same as CAL2
            max_i = num_s;
            max_h = H[num_s];
            for(i=0;i<num_s;i=i+1)
            begin
                if(H[i] > max_h)
                begin
                    max_h = H[i];
                    max_i = i;
                end
            end

            if(max_h > $signed(maxi))
            begin
                maxi_n = max_h;
                //refi_n = count;
                refi_n = ((count-max_i+num_r) > num_r+1)? count-max_i-1 : count-max_i+num_r;
                queryi_n = (count > max_i+1)? max_i+1+(1+num_s)*row :  max_i+1+(1+num_s)*(row-1);
            end
            else
            begin
                maxi_n = maxi;
                queryi_n = queryi;
                refi_n = refi;
            end
        end

        default:
        begin
            max_h = 8'd0;
            max_i = 6'd0;
            maxi_n = maxi;
            queryi_n = queryi;
            refi_n = refi;
        end
    endcase
end


//------------------------------------------------------------------
// sequential part
//------------------------------------------------------------------
always@(posedge clk or posedge reset)
begin
    if(reset)
    begin
        state <= IDLE;
        count <= 7'd0;
        row <= 2'd0;
        for(i=0;i<=num_q;i=i+1)
        begin
            query[i] <= 2'd1;      //should not matter
        end
        for(i=0;i<=num_r;i=i+1)
        begin
            ref[i] <= 2'd0;        //should not matter
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            S_query[i] <= 2'd1;
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            S_ref[i] <= 2'd0;
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            S[i] <= mismatch;
        end
        for(i=0;i<=num_q;i=i+1)
        begin
            I0[i] <= gopen;
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            I[i] <= gopen;
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            D[i] <= gopen;
        end
        for(i=0;i<=num_2s;i=i+1)
        begin
            H[i] <= zero;
        end
        for(i=0;i<=num_h0;i=i+1)
        begin
            H0[i] <= zero;
        end

        maxi <= 8'd0;
        queryi <= 6'd0;
        refi <= 7'd0;
    end
    else
    begin
        case(state)
            IDLE:
            begin
                S_ref[0] <= (valid==1)? data_ref : 2'd0; // initial ref = 0, query = 1, resulting mismatch
                for(i=1;i<=num_s;i=i+1)
                begin
                    S_ref[i] <= S_ref[i-1];
                end
                for(i=0;i<=num_h0;i=i+1)
                begin
                    H0[i] <= H0[i-1];
                end
                for(i=0;i<=num_q;i=i+1)
                begin
                    I0[i] <= I0[i];
                end
            end
            CAL1:
            begin
                S_ref[0] <= data_ref; // initial ref = 0, query = 1, resulting mismatch
                for(i=1;i<=num_s;i=i+1)
                begin
                    S_ref[i] <= S_ref[i-1];
                end
                H0[0] <= (count[6:4] > 3'd0)? H[15] : 8'd0;    // 8'hFE = -2
                for(i=1;i<=num_h0;i=i+1)
                begin
                    H0[i] <= H0[i-1];
                end
                I0[0] <= (count>=num_s)? I[num_s] : gopen;
                for(i=1;i<=num_q;i=i+1)
                begin
                    I0[i] <= I0[i-1];
                end
            end
            CAL2:
            begin
                S_ref[0] <= ref[count]; // initial ref = 0, query = 1, resulting mismatch
                for(i=1;i<=num_s;i=i+1)
                begin
                    S_ref[i] <= S_ref[i-1];
                end
                H0[0] <= (count == 7'd16)?  8'd0 : H[15];  //right-bottom corner on every row is not needed,
                for(i=1;i<=num_h0;i=i+1)
                begin
                    H0[i] <= H0[i-1];
                end
                I0[0] <= I[num_s];
                for(i=1;i<=num_q;i=i+1)
                begin
                    I0[i] <= I0[i-1];
                end
            end
            CAL3:
            begin
                S_ref[0] <= 2'd0; // initial ref = 0, query = 1, resulting mismatch
                for(i=1;i<=num_s;i=i+1)
                begin
                    S_ref[i] <= S_ref[i-1];
                end
                H0[0] <= (count == 7'd16)?  8'd0 : H[15];  //right-bottom corner on every row is not needed,
                for(i=1;i<=num_h0;i=i+1)
                begin
                    H0[i] <= H0[i-1];
                end
                I0[0] <= I[num_s];
                for(i=1;i<=num_q;i=i+1)
                begin
                    I0[i] <= I0[i-1];
                end
            end
            default:
            begin // initial ref = 0, query = 1, resulting mismatch
                for(i=0;i<=num_s;i=i+1)
                begin
                    S_ref[i] <= S_ref[i-1];
                end
                for(i=0;i<=num_h0;i=i+1)
                begin
                    H0[i] <= H0[i-1];
                end
                for(i=0;i<=num_q;i=i+1)
                begin
                    I0[i] <= I0[i];
                end
            end



        endcase
        state <= state_n;
        count <= count_n;
        row <= row_n;
        for(i=0;i<=num_q;i=i+1)
        begin
            query[i] <= query_n[i];
        end
        for(i=0;i<=num_r;i=i+1)
        begin
            ref[i] <= ref_n[i];
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            S_query[i] <= S_query_n[i];
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            S[i] <= S_n[i];
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            I[i] <= I_n[i];
        end
        for(i=0;i<=num_s;i=i+1)
        begin
            D[i] <= D_n[i];
        end
        for(i=0;i<=num_2s;i=i+1)
        begin
            H[i] <= H_n[i];
        end
        maxi <= maxi_n;
        queryi <= queryi_n;
        refi <= refi_n;
    end
end

endmodule
