// ====================================================================
// Transaction Object Start
// ====================================================================
class gen_item; // GEN -> DRV
    rand int    dp_num  ;   // # Dispatch
    rand int    cp_num  ;   // # Complete

    function void print (string msg_tag="");
        $display("T=%0t %s Generator requests #Dispatch=%0d, #Complete=%0d",
                $time, msg_tag, dp_num, cp_num);
    endfunction // print
endclass // gen_item
// ====================================================================
// Transaction Object End
// ====================================================================

// ====================================================================
// Driver Start
// ====================================================================
class driver;
    virtual pipeline_dp_if                  vif                     ;
    mailbox                                 drv_mbx                 ;
    event                                   drv_done                ;
    logic   [`THREAD_IDX_WIDTH-1:0]         thread_sel              ;
    logic   [`THREAD_NUM-1:0][`XLEN-1:0]    pc                      ;
    logic   [`XLEN-1:0]                     inst_pc                 ;
    logic   [`XLEN-1:0]                     program_mem_addr        ;
    logic   [64-1:0]                        program_mem_data        ;
    logic   [64-1:0]                        program_mem     [`MEM_64BIT_LINES-1:0];

    task run();
        $display("T=%0t [Driver] starting ...", $time);

        for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            pc[thread_idx]  =   thread_idx * 'h100;
        end
        thread_sel  =   0;

        @(negedge vif.clk_i);

        $display("T=%0t [Driver] Reading program.mem", $time);
        $readmemh("program_smt.mem", program_mem);

        forever begin
            // gen_item    item;
            // drv_mbx.get(item);


            /////////////////////////////////////////////////////////////////////////
            vif.fiq_dp.avail_num =   `DP_NUM;
            for (int unsigned dp_idx = 0; dp_idx < `DP_NUM; dp_idx++) begin
                vif.fiq_dp.thread_idx[dp_idx] = thread_sel;
            end
            /////////////////////////////////////////////////////////////////////////

            for (int unsigned dp_idx = 0; dp_idx < `DP_NUM; dp_idx++) begin
                inst_pc                 =   pc[thread_sel] + dp_idx * 4;
                program_mem_addr        =   {3'b0, inst_pc[`XLEN-1:3]};
                program_mem_data        =   program_mem[program_mem_addr];
                vif.fiq_dp.pc[dp_idx]   =   inst_pc;
                vif.fiq_dp.inst[dp_idx] =   inst_pc[2] ? program_mem_data[63:32] : program_mem_data[31:0];
            end

            /////////////////////////////////////////////////////////////////////////
            //Move PC
            @(posedge vif.clk_i);
            for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
                if (vif.rst_i) begin
                    pc[thread_idx]  =   thread_idx * 'h100;
                end else if (vif.br_mis_mon_o.valid[thread_idx]) begin
                    pc[thread_idx]  =   vif.br_mis_mon_o.br_target[thread_idx];
                end else if (thread_sel == thread_idx) begin
                    pc[thread_idx]  =   pc[thread_idx] + vif.dp_fiq.dp_num * 4;
                end
            end
            /////////////////////////////////////////////////////////////////////////

            $display("T=%0t [Driver] PC=%0h, dp_num=%0d", $time, pc, vif.dp_fiq.dp_num);

            @(negedge vif.clk_i);
            vif.fiq_dp      =   0;
            vif.exception_i =   0;
            thread_sel      =   thread_sel + 'd1;
            // ->drv_done;
        end
    endtask // run()

endclass //
// ====================================================================
// Driver End
// ====================================================================

// ====================================================================
// Scoreboard Start
// ====================================================================

// ====================================================================
// Scoreboard End
// ====================================================================

// ====================================================================
// Monitor Start
// ====================================================================
class monitor;
    virtual pipeline_dp_if      vif                             ;
    mailbox                     scb_mbx                         ;
    logic   [`XLEN-1:0]         wfi_pc      [`THREAD_NUM-1:0]   ;
    int                         wb_fileno   [`THREAD_NUM-1:0]   ;
    string                      wb_filename                     ;
    logic   [`THREAD_NUM-1:0]   wfi_flag                        ;

    task run();
        $display("T=%0t [Monitor] starting ...", $time);
        
        // Open writeback.out
        for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            wb_filename             =   {"writeback_t", (thread_idx + 'd48), ".out"};
            wb_fileno[thread_idx]   =   $fopen(wb_filename);
        end

        // Initialize wfi_pc
        for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            wfi_pc[thread_idx]      =   32'hFFFFFFFF;
            wfi_flag[thread_idx]    =   1'b0        ;
        end

        // wfi_flag[1] =   1'b1;

        forever begin
            @(posedge vif.clk_i);
            // If the first WFI instruction is dispatched, record its PC
            // wfi_pc is used to compare with the PC retired.
            // Testbench calls $finish if the retired PC match wfi_pc
            for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
                if (wfi_pc[thread_idx] == 32'hFFFFFFFF) begin
                    for (int unsigned dp_idx = 0; dp_idx < `DP_NUM; dp_idx++) begin
                        if (dp_idx < vif.dp_rs_mon_o.dp_num 
                        && vif.dp_rs_mon_o.dec_inst[dp_idx].halt == `TRUE
                        && vif.dp_rs_mon_o.dec_inst[dp_idx].thread_idx == thread_idx) begin
                            wfi_pc[thread_idx]  =   vif.dp_rs_mon_o.dec_inst[dp_idx].pc;
                        end
                    end
                end
            end

            $display("%0d", vif.fiq_dp.avail_num);
            print_rob(vif.rob_mon_o, vif.rob_head_mon_o, vif.rob_tail_mon_o);
            print_rs(vif.rs_mon_o, vif.rs_cod_mon_o);
            print_mt(vif.mt_mon_o);
            print_amt(vif.amt_mon_o);
            print_prf(vif.prf_mon_o);
            print_ALU_ib(vif.ALU_queue_mon_o, vif.ALU_valid_mon_o, vif.ALU_head_mon_o, vif.ALU_tail_mon_o);
            // print_MULT_ib(vif.MULT_queue_mon_o, vif.MULT_valid_mon_o, vif.MULT_head_mon_o, vif.MULT_tail_mon_o);
            // print_BR_ib(vif.BR_queue_mon_o, vif.BR_valid_mon_o, vif.BR_head_mon_o, vif.BR_tail_mon_o);
            print_fl(vif.fl_mon_o);
            //print_vfl(vif.vfl_fl_mon_o);
            // print_mt_dp(vif.dp_mt_mon_o, vif.mt_dp_mon_o);
            print_cdb(vif.cdb_mon_o);
            // print_rt(vif.rt_pc_o, vif.rt_valid_o, vif.rob_amt_mon_o, vif.rob_fl_mon_o, vif.prf_mon_o);

            // Monitor Retire
            for (int unsigned thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
                for (int unsigned rt_idx = 0; rt_idx < `RT_NUM; rt_idx++) begin
                // Record write back of every retire to writeback.out
                    if (vif.rt_valid_o[thread_idx][rt_idx]) begin
                        if ((vif.rob_amt_mon_o[thread_idx][rt_idx].arch_reg != `ZERO_REG)
                        && (vif.rob_amt_mon_o[thread_idx][rt_idx].wr_en == 1'b1)) begin
                            $fdisplay(wb_fileno[thread_idx], "PC=%x, REG[%d]=%x",
                                (vif.rt_pc_o[thread_idx][rt_idx] - thread_idx * 'h100),
                                vif.rob_amt_mon_o[thread_idx][rt_idx].arch_reg,
                                vif.prf_mon_o[vif.rob_amt_mon_o[thread_idx][rt_idx].phy_reg]);
                        end else begin
                            $fdisplay(wb_fileno[thread_idx], "PC=%x, ---", 
                            (vif.rt_pc_o[thread_idx][rt_idx] - thread_idx * 'h100));
                        end
                    end

                    // Check if the retired PC matches wfi_pc.
                    // If matched, exit.
                    if (vif.rt_valid_o[thread_idx][rt_idx]
                    && vif.rt_pc_o[thread_idx][rt_idx] == wfi_pc[thread_idx]) begin
                        wfi_flag[thread_idx]    =   1'b1;
                        $display("T=%0t [Monitor] WFI instruction retired at PC=%0h, exit thread %0d", $time, wfi_pc[thread_idx], thread_idx);
                    end
                end
            end

            if (&wfi_flag == 1) begin
                $display("All the threads are completed. exit program.");
                $finish;
            end
        end
    endtask

    function void print_rob(
        ROB_ENTRY   [`THREAD_NUM-1:0][`ROB_ENTRY_NUM-1:0]    rob_mon         ,
        logic       [`THREAD_NUM-1:0][`ROB_IDX_WIDTH-1:0]    rob_head_mon    ,
        logic       [`THREAD_NUM-1:0][`ROB_IDX_WIDTH-1:0]    rob_tail_mon
    );
        for(int thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            $display("T=%0t ROB[%0d] Contents", $time, thread_idx);
            $display("head=%0d, tail=%0d", rob_head_mon[thread_idx], rob_tail_mon[thread_idx]);
            $display("Index\t|valid\t|PC\t|rd\t|told\t|tag\t|br_predict\t|br_result\t|br_target\t|complete");      
            for (int entry_idx = 0; entry_idx < `ROB_ENTRY_NUM; entry_idx++) begin
                $display("%0d\t|%0d\t|%0h\t|%0d\t|%0d\t|%0d\t|%0d\t\t|%0d\t\t|%0d\t\t|%0d",
                entry_idx                                   ,
                rob_mon[thread_idx][entry_idx].valid        ,
                rob_mon[thread_idx][entry_idx].pc           ,
                rob_mon[thread_idx][entry_idx].rd           ,
                rob_mon[thread_idx][entry_idx].tag_old      ,
                rob_mon[thread_idx][entry_idx].tag          ,
                rob_mon[thread_idx][entry_idx].br_predict   ,
                rob_mon[thread_idx][entry_idx].br_result    ,
                rob_mon[thread_idx][entry_idx].br_target    ,
                rob_mon[thread_idx][entry_idx].complete     
                );
            end
        end
    endfunction

    function void print_rs(RS_ENTRY [`RS_ENTRY_NUM-1:0] rs_mon, logic [$clog2(`RS_ENTRY_NUM)-1:0] rs_cod_mon);
        string  op_string   ;
        $display("T=%0t RS Contents", $time);
        $display("RS COD=%0d", rs_cod_mon);
        $display("Index\t|op\t|valid\t|PC\t|tag\t|tag1\t|ready\t|tag2\t|ready\t|rob_idx");
        for (int entry_idx = 0; entry_idx < `RS_ENTRY_NUM; entry_idx++) begin
            if (rs_mon[entry_idx].dec_inst.rd_mem   ) begin
                op_string   =   "LD";
            end else if (rs_mon[entry_idx].dec_inst.wr_mem   ) begin
                op_string   =   "ST";
            end else if (rs_mon[entry_idx].dec_inst.cond_br  ) begin
                op_string   =   "CBR";
            end else if (rs_mon[entry_idx].dec_inst.uncond_br) begin
                op_string   =   "UBR";
            end else if (rs_mon[entry_idx].dec_inst.halt     ) begin
                op_string   =   "WFI";
            end else if (rs_mon[entry_idx].dec_inst.illegal  ) begin
                op_string   =   "ILL";
            end else if (rs_mon[entry_idx].dec_inst.csr_op   ) begin
                op_string   =   "CSR";
            end else if (rs_mon[entry_idx].dec_inst.alu      ) begin
                op_string   =   "ALU";
            end else if (rs_mon[entry_idx].dec_inst.mult     ) begin
                op_string   =   "MUL";
            end else begin
                op_string   =   "-";
            end
            $display("%0d\t|%s\t|%0d\t|%0h\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d",
            entry_idx                               ,
            op_string                               ,
            rs_mon[entry_idx].valid                 ,
            rs_mon[entry_idx].dec_inst.pc           ,
            rs_mon[entry_idx].dec_inst.tag          ,
            rs_mon[entry_idx].dec_inst.tag1         ,
            rs_mon[entry_idx].dec_inst.tag1_ready   ,
            rs_mon[entry_idx].dec_inst.tag2         ,
            rs_mon[entry_idx].dec_inst.tag2_ready   ,
            rs_mon[entry_idx].dec_inst.rob_idx      
            );
        end
    endfunction

    function void print_mt(MT_ENTRY [`THREAD_NUM-1:0][`ARCH_REG_NUM-1:0] mt_mon);
        for(int thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            $display("T=%0t MT[%0d] Contents", $time, thread_idx);
            $display("arch\t|tag\t|ready\t|arch\t|tag\t|ready\t");
            for (int arch_idx = 0; arch_idx < `ARCH_REG_NUM/2; arch_idx++) begin
                $display("%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t", 
                arch_idx, mt_mon[thread_idx][arch_idx].tag, mt_mon[thread_idx][arch_idx].tag_ready,
                arch_idx+`ARCH_REG_NUM/2, mt_mon[thread_idx][arch_idx+`ARCH_REG_NUM/2].tag, mt_mon[thread_idx][arch_idx+`ARCH_REG_NUM/2].tag_ready);
            end
        end
    endfunction

    function void print_amt(AMT_ENTRY [`THREAD_NUM-1:0][`ARCH_REG_NUM-1:0] amt_mon);
        for(int thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            $display("T=%0t AMT[%0d] Contents", $time, thread_idx);
            $display("arch\t|tag\t|arch\t|tag\t|arch\t|tag\t|arch\t|tag\t");
            for (int arch_idx = 0; arch_idx < `ARCH_REG_NUM/4; arch_idx++) begin
                $display("%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t", 
                arch_idx, amt_mon[thread_idx][arch_idx].amt_tag,
                arch_idx+`ARCH_REG_NUM/4, amt_mon[thread_idx][arch_idx+`ARCH_REG_NUM/4].amt_tag,
                arch_idx+`ARCH_REG_NUM/2, amt_mon[thread_idx][arch_idx+`ARCH_REG_NUM/2].amt_tag,
                arch_idx+`ARCH_REG_NUM*3/4, amt_mon[thread_idx][arch_idx+`ARCH_REG_NUM*3/4].amt_tag,
                );
            end
        end
    endfunction

    function void print_ALU_ib(
        IS_INST     [`ALU_Q_SIZE-1:0]       ALU_queue_mon   , 
        logic       [`ALU_Q_SIZE-1:0]       ALU_valid_mon   ,
        logic       [`ALU_IDX_WIDTH-1:0]    ALU_head_mon    ,
        logic       [`ALU_IDX_WIDTH-1:0]    ALU_tail_mon    
    );
        $display("T=%0t ALU IB Queue Contents", $time);
        $display("head=%0d, tail=%0d", ALU_head_mon, ALU_tail_mon);
        $display("Index\t|valid\t|PC\t|rs1\t|rs2\t|tag\t|rob_idx\t");
        for (int entry_idx = 0; entry_idx < `ALU_Q_SIZE; entry_idx++) begin
            $display("%0d\t|%0d\t|%0h\t|%0d\t|%0d\t|%0d\t|%0d\t", 
            entry_idx,
            ALU_valid_mon[entry_idx],
            ALU_queue_mon[entry_idx].pc,
            ALU_queue_mon[entry_idx].rs1_value,
            ALU_queue_mon[entry_idx].rs2_value,
            ALU_queue_mon[entry_idx].tag,
            ALU_queue_mon[entry_idx].rob_idx
            );
        end
    endfunction

    function void print_MULT_ib(
        IS_INST     [`MULT_Q_SIZE-1:0]      MULT_queue_mon  ,
        logic       [`MULT_Q_SIZE-1:0]      MULT_valid_mon  ,
        logic       [`MULT_IDX_WIDTH-1:0]   MULT_head_mon   ,
        logic       [`MULT_IDX_WIDTH-1:0]   MULT_tail_mon    
    );
        $display("T=%0t MULT IB Queue Contents", $time);
        $display("head=%0d, tail=%0d", MULT_head_mon, MULT_tail_mon);
        $display("Index\t|valid\t|PC\t|rs1\t|rs2\t|tag\t|rob_idx\t");
        for (int entry_idx = 0; entry_idx < `MULT_Q_SIZE; entry_idx++) begin
            $display("%0d\t|%0d\t|%0h\t|%0d\t|%0d\t|%0d\t|%0d\t", 
            entry_idx,
            MULT_valid_mon[entry_idx],
            MULT_queue_mon[entry_idx].pc,
            MULT_queue_mon[entry_idx].rs1_value,
            MULT_queue_mon[entry_idx].rs2_value,
            MULT_queue_mon[entry_idx].tag,
            MULT_queue_mon[entry_idx].rob_idx
            );
        end
    endfunction

    function void print_BR_ib(
        IS_INST     [`BR_Q_SIZE-1:0]        BR_queue_mon    , 
        logic       [`BR_Q_SIZE-1:0]        BR_valid_mon    ,
        logic       [`BR_IDX_WIDTH-1:0]     BR_head_mon     ,
        logic       [`BR_IDX_WIDTH-1:0]     BR_tail_mon    
    );
        $display("T=%0t BR IB Queue Contents", $time);
        $display("head=%0d, tail=%0d", BR_head_mon, BR_tail_mon);
        $display("Index\t|valid\t|PC\t|rs1\t|rs2\t|tag\t|rob_idx\t");
        for (int entry_idx = 0; entry_idx < `BR_Q_SIZE; entry_idx++) begin
            $display("%0d\t|%0d\t|%0h\t|%0d\t|%0d\t|%0d\t|%0d\t", 
            entry_idx,
            BR_valid_mon[entry_idx],
            BR_queue_mon[entry_idx].pc,
            BR_queue_mon[entry_idx].rs1_value,
            BR_queue_mon[entry_idx].rs2_value,
            BR_queue_mon[entry_idx].tag,
            BR_queue_mon[entry_idx].rob_idx
            );
        end
    endfunction

    function void print_prf(logic   [`PHY_REG_NUM-1:0] [`XLEN-1:0] prf_mon_o);
        $display("T=%0t PRF Contents", $time);
        $display("addr\t|data\t\t|addr\t|data\t\t|addr\t|data\t\t|addr\t|data\t\t");
        // $display("%0d", `PHY_REG_NUM/4);
        for (int reg_idx = 0; reg_idx < `PHY_REG_NUM/4; reg_idx++) begin
            $display("%0d\t|%8h\t|%0d\t|%8h\t|%0d\t|%8h\t|%0d\t|%8h\t", 
            reg_idx, prf_mon_o[reg_idx], 
            reg_idx+`PHY_REG_NUM/4, prf_mon_o[reg_idx+`PHY_REG_NUM/4],
            reg_idx+`PHY_REG_NUM/2, prf_mon_o[reg_idx+`PHY_REG_NUM/2],
            reg_idx+`PHY_REG_NUM*3/4, prf_mon_o[reg_idx+`PHY_REG_NUM*3/4]);
        end
    endfunction

    function void print_fl(FL_ENTRY [`FL_ENTRY_NUM-1:0] fl_mon);
        $display("T=%0t FL Contents", $time);
        $display("Index\t|Tag\t|TID\t|valid\t|Index\t|Tag\t|TID\t|valid\t|Index\t|Tag\t|TID\t|valid\t|Index\t|Tag\t|TID\t|valid\t|Index\t|Tag\t|TID\t|valid\t");
        // $display("%0d", `FL_ENTRY_NUM/4);
        for (int fl_idx = 0; fl_idx < `FL_ENTRY_NUM/5; fl_idx++) begin
            $display("%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t", 
            fl_idx, fl_mon[fl_idx].tag, fl_mon[fl_idx].thread_idx, fl_mon[fl_idx].valid,
            fl_idx+`FL_ENTRY_NUM/5, fl_mon[fl_idx+`FL_ENTRY_NUM/5].tag, fl_mon[fl_idx+`FL_ENTRY_NUM/5].thread_idx, fl_mon[fl_idx+`FL_ENTRY_NUM/5].valid,
            fl_idx+`FL_ENTRY_NUM*2/5, fl_mon[fl_idx+`FL_ENTRY_NUM*2/5].tag, fl_mon[fl_idx+`FL_ENTRY_NUM*2/5].thread_idx, fl_mon[fl_idx+`FL_ENTRY_NUM*2/5].valid,
            fl_idx+`FL_ENTRY_NUM*3/5, fl_mon[fl_idx+`FL_ENTRY_NUM*3/5].tag, fl_mon[fl_idx+`FL_ENTRY_NUM*3/5].thread_idx, fl_mon[fl_idx+`FL_ENTRY_NUM*3/5].valid,
            fl_idx+`FL_ENTRY_NUM*4/5, fl_mon[fl_idx+`FL_ENTRY_NUM*4/5].tag, fl_mon[fl_idx+`FL_ENTRY_NUM*4/5].thread_idx, fl_mon[fl_idx+`FL_ENTRY_NUM*3/5].valid);
        end
    endfunction

    // function void print_vfl(FL_ENTRY [`FL_ENTRY_NUM-1:0]  vfl_fl_mon);
    //     $display("T=%0t VFL Contents", $time);
    //     $display("Index\t|Tag\t|Index\t|Tag\t|Index\t|Tag\t|Index\t|Tag\t");
    //     // $display("%0d", `FL_ENTRY_NUM/4);
    //     for (int fl_idx = 0; fl_idx < `FL_ENTRY_NUM/4; fl_idx++) begin
    //         $display("%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t|%0d\t", 
    //         fl_idx, vfl_fl_mon[fl_idx].tag, 
    //         fl_idx+`FL_ENTRY_NUM/4, vfl_fl_mon[fl_idx+`FL_ENTRY_NUM/4].tag,
    //         fl_idx+`FL_ENTRY_NUM/2, vfl_fl_mon[fl_idx+`FL_ENTRY_NUM/2].tag,
    //         fl_idx+`FL_ENTRY_NUM*3/4, vfl_fl_mon[fl_idx+`FL_ENTRY_NUM*3/4].tag);
    //     end
    // endfunction

    function void print_mt_dp(
        DP_MT       [`THREAD_NUM-1:0][`DP_NUM-1:0]   dp_mt_mon   ,
        MT_DP       [`THREAD_NUM-1:0][`DP_NUM-1:0]   mt_dp_mon   
    );
        for(int thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            $display("thread_idx=%0d", thread_idx);
            for (int dp_idx = 0; dp_idx < `DP_NUM; dp_idx++) begin
                $display("T=%0t DP_MT[%0d] rs1=%0d, rs2=%0d, rd=%0d, tag=%0d, wr_en=%0d, thread_idx=%0d",
                    $time, dp_idx       ,
                    dp_mt_mon[thread_idx][dp_idx].rs1       ,
                    dp_mt_mon[thread_idx][dp_idx].rs2       ,
                    dp_mt_mon[thread_idx][dp_idx].rd        ,
                    dp_mt_mon[thread_idx][dp_idx].tag       ,
                    dp_mt_mon[thread_idx][dp_idx].wr_en     ,
                    dp_mt_mon[thread_idx][dp_idx].thread_idx);

                $display("T=%0t MT_DP[%0d] tag1=%0d, tag1_ready=%0d, tag2=%0d, tag2_ready=%0d, tag_old=%0d",
                    $time, dp_idx       ,
                    mt_dp_mon[thread_idx][dp_idx].tag1      ,
                    mt_dp_mon[thread_idx][dp_idx].tag1_ready,
                    mt_dp_mon[thread_idx][dp_idx].tag2      ,
                    mt_dp_mon[thread_idx][dp_idx].tag2_ready,
                    mt_dp_mon[thread_idx][dp_idx].tag_old   );
                end
            end
    endfunction

    function void print_cdb(CDB [`CDB_NUM-1:0] cdb_mon);
        for (int cp_idx = 0; cp_idx < `CDB_NUM; cp_idx++) begin
            $display("T=%0t CDB[%0d] valid=%0d, pc=%0h, tag=%0d, rob_idx=%0d, thread_idx=%0d, br_result=%0d, br_traget=%0d",
                $time, cp_idx, 
                cdb_mon[cp_idx].valid     ,
                cdb_mon[cp_idx].pc        ,
                cdb_mon[cp_idx].tag       ,
                cdb_mon[cp_idx].rob_idx   ,
                cdb_mon[cp_idx].thread_idx,
                cdb_mon[cp_idx].br_result ,
                cdb_mon[cp_idx].br_target );
        end
    endfunction

    function void print_rt(
        logic   [`RT_NUM-1:0][`XLEN-1:0]        rt_pc           ,
        logic   [`RT_NUM-1:0]                   rt_valid        ,
        ROB_AMT [`THREAD_NUM-1:0][`RT_NUM-1:0]  rob_amt_mon     ,
        ROB_FL  [`THREAD_NUM-1:0]               rob_fl_mon      ,
        logic   [`PHY_REG_NUM-1:0][`XLEN-1:0]   prf_mon         
    );
        for(int thread_idx = 0; thread_idx < `THREAD_NUM; thread_idx++) begin
            $display("thread_idx=%0d", thread_idx);
            for (int rt_idx = 0; rt_idx < `RT_NUM; rt_idx++) begin
                $display("T=%0t RT[%0d] valid=%0d, pc=%0h, rd=%0d, tag=%0d, told=%0d, rd_value=%0d",
                    $time, rt_idx, 
                    rt_valid[rt_idx]                        ,
                    rt_pc[rt_idx]                           ,
                    rob_amt_mon[thread_idx][rt_idx].arch_reg            ,
                    rob_amt_mon[thread_idx][rt_idx].phy_reg             ,
                    rob_fl_mon[thread_idx].tag_old[rt_idx]              ,
                    prf_mon[rob_amt_mon[thread_idx][rt_idx].phy_reg]
                );
            end
        end
    endfunction

endclass
// ====================================================================
// Monitor End
// ====================================================================

// ====================================================================
// Generator Start
// ====================================================================
class generator;
    mailbox drv_mbx;
    event   drv_done;
    int     num     =   200;

    task run();
        for (int i = 0; i < num; i++) begin
            gen_item item   =   new;
            item.randomize();
            // $display("T=%0t [Generator] Loop:%0d/%0d create next item",
            //         $time, i+1, num);
            // item.print("[Generator]");
            drv_mbx.put(item);
            @(drv_done);
        end
        $display("T=%0t [Generator] Done generation of %0d items",
                $time, num);
    endtask // run()
endclass
// ====================================================================
// Generator End
// ====================================================================

// ====================================================================
// Environment Start
// ====================================================================
class env;
    driver          d0          ;   // driver     handle
    monitor         m0          ;   // monitor    handle
    generator       g0          ;   // generator  handle
    // scoreboard      s0          ;   // scoreboard handle

    mailbox         drv_mbx     ;   // Connect generator  <-> driver
    mailbox         scb_mbx     ;   // Connect monitor    <-> scoreboard
    event           drv_done    ;   // Indicates when driver is done

    virtual pipeline_dp_if  vif ;   // Virtual interface handle

    function new();
        d0          =   new         ;
        m0          =   new         ;
        g0          =   new         ;
        // s0          =   new         ;
        
        drv_mbx     =   new()       ;
        scb_mbx     =   new()       ;

        d0.drv_mbx  =   drv_mbx     ;
        g0.drv_mbx  =   drv_mbx     ;
        m0.scb_mbx  =   scb_mbx     ;
        // s0.scb_mbx  =   scb_mbx     ;

        d0.drv_done =   drv_done    ;
        g0.drv_done =   drv_done    ;
    endfunction // new()

    virtual task run();
        d0.vif  =   vif;
        m0.vif  =   vif;

        fork
            d0.run();
            m0.run();
            g0.run();
            // s0.run();
        join_any
    endtask // run()
endclass // env
// ====================================================================
// Environment End
// ====================================================================

// ====================================================================
// Test Start
// ====================================================================
class test;
    env e0;
    function new();
        e0  =   new;
    endfunction // new()

    task run();
        e0.run();
    endtask // run()
endclass // test
// ====================================================================
// Test End
// ====================================================================

// ====================================================================
// Interface Start
// ====================================================================
interface pipeline_dp_if (input bit clk_i);
    logic                                               rst_i               ;   // Reset
    FIQ_DP                                              fiq_dp              ;   // From FIQ to DP
    DP_FIQ                                              dp_fiq              ;   // From DP to FIQ
    logic                                               exception_i         ;   // External exception
    // Testing
    //      Dispatch
    DP_RS                                               dp_rs_mon_o         ;   // From Dispatcher to RS
    DP_MT       [`THREAD_NUM-1:0][`DP_NUM-1:0]          dp_mt_mon_o         ;
    MT_DP       [`THREAD_NUM-1:0][`DP_NUM-1:0]          mt_dp_mon_o         ;
    //      Issue
    RS_IB                                               rs_ib_mon_o         ;   // From RS to IB
    //      Execute
    IB_FU       [`FU_NUM-1:0]                           ib_fu_mon_o         ;   // From IB to FU
    //      Complete
    FU_BC                                               fu_bc_mon_o         ;   // From FU to BC
    CDB         [`CDB_NUM-1:0]                          cdb_mon_o           ;   // CDB
    //      Retire
    logic       [`THREAD_NUM-1:0][`RT_NUM-1:0][`XLEN-1:0]   rt_pc_o             ;   // PC of retired instructions
    logic       [`THREAD_NUM-1:0][`RT_NUM-1:0]              rt_valid_o          ;   // Retire valid
    ROB_AMT     [`THREAD_NUM-1:0][`RT_NUM-1:0]          rob_amt_mon_o       ;   // From ROB to AMT
    ROB_FL      [`THREAD_NUM-1:0]                       rob_fl_mon_o        ;   // From ROB to FL
    //ROB_VFL                                           rob_vfl_mon_o       ;   // From ROB to VFL
    BR_MIS                                              br_mis_mon_o        ;   // Branch Misprediction
    //      Contents
    ROB_ENTRY   [`THREAD_NUM-1:0][`ROB_ENTRY_NUM-1:0]   rob_mon_o           ;   // ROB contents monitor
    logic       [`THREAD_NUM-1:0][`ROB_IDX_WIDTH-1:0]   rob_head_mon_o      ;   // ROB head pointer
    logic       [`THREAD_NUM-1:0][`ROB_IDX_WIDTH-1:0]   rob_tail_mon_o      ;   // ROB tail pointer
    RS_ENTRY    [`RS_ENTRY_NUM-1:0]                     rs_mon_o            ;   // RS contents monitor
    logic       [$clog2(`RS_ENTRY_NUM)-1:0]             rs_cod_mon_o        ;
    MT_ENTRY    [`THREAD_NUM-1:0][`ARCH_REG_NUM-1:0]    mt_mon_o            ;   // Map Table contents monitor
    AMT_ENTRY   [`THREAD_NUM-1:0][`ARCH_REG_NUM-1:0]    amt_mon_o           ;  // Arch Map Table contents monitor
    FL_ENTRY    [`FL_ENTRY_NUM-1:0]                     fl_mon_o            ;   // Freelist contents monitor
    //logic       [`FL_IDX_WIDTH-1:0]                   fl_head_mon_o       ;
    //logic       [`FL_IDX_WIDTH-1:0]                   fl_tail_mon_o       ;
    //FL_ENTRY    [`FL_ENTRY_NUM-1:0]                   vfl_fl_mon_o        ;
    IS_INST     [`ALU_Q_SIZE  -1:0]                     ALU_queue_mon_o     ;   // IB queue monitor
    IS_INST     [`MULT_Q_SIZE -1:0]                     MULT_queue_mon_o    ;   // IB queue monitor
    IS_INST     [`BR_Q_SIZE   -1:0]                     BR_queue_mon_o      ;   // IB queue monitor
    IS_INST     [`LOAD_Q_SIZE -1:0]                     LOAD_queue_mon_o    ;   // IB queue monitor
    IS_INST     [`STORE_Q_SIZE-1:0]                     STORE_queue_mon_o   ;   // IB queue monitor
    logic       [`ALU_Q_SIZE  -1:0]                     ALU_valid_mon_o     ;   // IB queue monitor
    logic       [`MULT_Q_SIZE -1:0]                     MULT_valid_mon_o    ;   // IB queue monitor
    logic       [`BR_Q_SIZE   -1:0]                     BR_valid_mon_o      ;   // IB queue monitor
    logic       [`LOAD_Q_SIZE -1:0]                     LOAD_valid_mon_o    ;   // IB queue monitor
    logic       [`STORE_Q_SIZE-1:0]                     STORE_valid_mon_o   ;   // IB queue monitor
    logic       [`ALU_IDX_WIDTH  -1:0]                  ALU_head_mon_o      ;   // IB queue pointer monitor
    logic       [`ALU_IDX_WIDTH  -1:0]                  ALU_tail_mon_o      ;   // IB queue pointer monitor
    logic       [`MULT_IDX_WIDTH -1:0]                  MULT_head_mon_o     ;   // IB queue pointer monitor
    logic       [`MULT_IDX_WIDTH -1:0]                  MULT_tail_mon_o     ;   // IB queue pointer monitor
    logic       [`BR_IDX_WIDTH   -1:0]                  BR_head_mon_o       ;   // IB queue pointer monitor
    logic       [`BR_IDX_WIDTH   -1:0]                  BR_tail_mon_o       ;   // IB queue pointer monitor
    logic       [`LOAD_IDX_WIDTH -1:0]                  LOAD_head_mon_o     ;   // IB queue pointer monitor
    logic       [`LOAD_IDX_WIDTH -1:0]                  LOAD_tail_mon_o     ;   // IB queue pointer monitor
    logic       [`STORE_IDX_WIDTH-1:0]                  STORE_head_mon_o    ;   // IB queue pointer monitor
    logic       [`STORE_IDX_WIDTH-1:0]                  STORE_tail_mon_o    ;   // IB queue pointer monitor
    logic       [`PHY_REG_NUM-1:0] [`XLEN-1:0]          prf_mon_o           ;   // Physical Register File monitor
endinterface // pipeline_dp_if
// ====================================================================
// Interface End
// ====================================================================

// ====================================================================
// Testbench Start
// ====================================================================
module pipeline_dp_tb;

// --------------------------------------------------------------------
// Local Parameters
// --------------------------------------------------------------------
    localparam  C_CLOCK_PERIOD  =   10;

// --------------------------------------------------------------------
// Signal Declarations
// --------------------------------------------------------------------
    logic           clk_i       ;

// --------------------------------------------------------------------
// Clock Generation
// --------------------------------------------------------------------
    initial begin
        clk_i   =   0;
        forever begin
            #(C_CLOCK_PERIOD/2) clk_i   =   ~clk_i;
        end
    end

// --------------------------------------------------------------------
// Interface Instantiation
// --------------------------------------------------------------------
    pipeline_dp_if  _if(clk_i);

// --------------------------------------------------------------------
// DUT Instantiation
// --------------------------------------------------------------------
    pipeline_dp_smt dut (
        .clk_i              (   clk_i               ),
        .rst_i              (_if.rst_i              ),
        .fiq_dp             (_if.fiq_dp             ),
        .dp_fiq             (_if.dp_fiq             ),
        .exception_i        (_if.exception_i        ),
        .dp_rs_mon_o        (_if.dp_rs_mon_o        ),
        .dp_mt_mon_o        (_if.dp_mt_mon_o        ),
        .mt_dp_mon_o        (_if.mt_dp_mon_o        ),
        .rs_ib_mon_o        (_if.rs_ib_mon_o        ),
        .ib_fu_mon_o        (_if.ib_fu_mon_o        ),
        .fu_bc_mon_o        (_if.fu_bc_mon_o        ),
        .cdb_mon_o          (_if.cdb_mon_o          ),
        .rt_pc_o            (_if.rt_pc_o            ),
        .rt_valid_o         (_if.rt_valid_o         ),
        .rob_amt_mon_o      (_if.rob_amt_mon_o      ),
        .rob_fl_mon_o       (_if.rob_fl_mon_o       ),
        //.rob_vfl_mon_o      (_if.rob_vfl_mon_o      ),
        .br_mis_mon_o       (_if.br_mis_mon_o       ),
        .rob_mon_o          (_if.rob_mon_o          ),
        .rob_head_mon_o     (_if.rob_head_mon_o     ),
        .rob_tail_mon_o     (_if.rob_tail_mon_o     ),
        .rs_mon_o           (_if.rs_mon_o           ),
        .rs_cod_mon_o       (_if.rs_cod_mon_o       ),
        .mt_mon_o           (_if.mt_mon_o           ),
        .amt_mon_o          (_if.amt_mon_o          ),
        .fl_mon_o           (_if.fl_mon_o           ),
        //.fl_head_mon_o      (_if.fl_head_mon_o      ),
        //.fl_tail_mon_o      (_if.fl_tail_mon_o      ),
        //.vfl_fl_mon_o       (_if.vfl_fl_mon_o       ),
        .ALU_queue_mon_o    (_if.ALU_queue_mon_o    ),
        .MULT_queue_mon_o   (_if.MULT_queue_mon_o   ),
        .BR_queue_mon_o     (_if.BR_queue_mon_o     ),
        .LOAD_queue_mon_o   (_if.LOAD_queue_mon_o   ),
        .STORE_queue_mon_o  (_if.STORE_queue_mon_o  ),
        .ALU_valid_mon_o    (_if.ALU_valid_mon_o    ),
        .MULT_valid_mon_o   (_if.MULT_valid_mon_o   ),
        .BR_valid_mon_o     (_if.BR_valid_mon_o     ),
        .LOAD_valid_mon_o   (_if.LOAD_valid_mon_o   ),
        .STORE_valid_mon_o  (_if.STORE_valid_mon_o  ),
        .ALU_head_mon_o     (_if.ALU_head_mon_o     ),   // IB queue pointer monitor
        .ALU_tail_mon_o     (_if.ALU_tail_mon_o     ),   // IB queue pointer monitor
        .MULT_head_mon_o    (_if.MULT_head_mon_o    ),   // IB queue pointer monitor
        .MULT_tail_mon_o    (_if.MULT_tail_mon_o    ),   // IB queue pointer monitor
        .BR_head_mon_o      (_if.BR_head_mon_o      ),   // IB queue pointer monitor
        .BR_tail_mon_o      (_if.BR_tail_mon_o      ),   // IB queue pointer monitor
        .LOAD_head_mon_o    (_if.LOAD_head_mon_o    ),   // IB queue pointer monitor
        .LOAD_tail_mon_o    (_if.LOAD_tail_mon_o    ),   // IB queue pointer monitor
        .STORE_head_mon_o   (_if.STORE_head_mon_o   ),   // IB queue pointer monitor
        .STORE_tail_mon_o   (_if.STORE_tail_mon_o   ),   // IB queue pointer monitor
        .prf_mon_o          (_if.prf_mon_o          )
    );
// --------------------------------------------------------------------

// --------------------------------------------------------------------
// Test Instantiation
// --------------------------------------------------------------------
    test    t0;

// --------------------------------------------------------------------
// Call test
// --------------------------------------------------------------------
    initial begin
        _if.rst_i       =   1;
        _if.fiq_dp      =   0;
        _if.exception_i =   0;
        // Apply reset and start stimulus
        #50 _if.rst_i   =   0;
        // $display("tail_o=%0b", _if.tail_o);

        t0  =   new;
        t0.e0.vif   =   _if;
        t0.run();

        // Because multiple components and clock are running
        // in the background, we need to call $finish explicitly
        $display("@@PASSED");
        #50 $finish;
    end

    // initial begin
    //     $dumpvars;
    //     $dumpfile("dump.vcd");
    // end

endmodule // ROB_tb

// ====================================================================
// Testbench End
// ====================================================================