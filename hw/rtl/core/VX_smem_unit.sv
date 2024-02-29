// Copyright © 2019-2023
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

module VX_smem_unit import VX_gpu_pkg::*; #(
    parameter CORE_ID = 0
) (
    input wire              clk,
    input wire              reset,
    
`ifdef PERF_ENABLE
    output cache_perf_t     cache_perf,
`endif

    VX_mem_bus_if.slave     dcache_bus_in_if [DCACHE_NUM_REQS],
    VX_mem_bus_if.master    dcache_bus_out_if [DCACHE_NUM_REQS]
);
    `STATIC_ASSERT(`IS_DIVISBLE((1 << `SMEM_LOG_SIZE), `MEM_BLOCK_SIZE), ("invalid parameter"))
    `STATIC_ASSERT(0 == (`SMEM_BASE_ADDR % (1 << `SMEM_LOG_SIZE)), ("invalid parameter"))

    localparam SMEM_ADDR_WIDTH = `SMEM_LOG_SIZE - `CLOG2(DCACHE_WORD_SIZE);
    localparam MEM_ASHIFT      = `CLOG2(`MEM_BLOCK_SIZE);
    localparam MEM_ADDRW       = `XLEN - MEM_ASHIFT;
    localparam SMEM_START_B    = MEM_ADDRW'(`XLEN'(`SMEM_BASE_ADDR) >> MEM_ASHIFT);
    localparam SMEM_END_B      = MEM_ADDRW'((`XLEN'(`SMEM_BASE_ADDR) + (1 << `SMEM_LOG_SIZE)) >> MEM_ASHIFT);

    VX_mem_bus_if #(
        .DATA_SIZE (DCACHE_WORD_SIZE),
        .TAG_WIDTH (DCACHE_TAG_WIDTH)
    ) smem_bus_if[DCACHE_NUM_REQS]();

    VX_mem_bus_if #(
        .DATA_SIZE (DCACHE_WORD_SIZE),
        .TAG_WIDTH (DCACHE_TAG_WIDTH)
    ) switch_out_bus_if[2 * DCACHE_NUM_REQS]();

    `RESET_RELAY (switch_reset, reset);

    for (genvar i = 0; i < DCACHE_NUM_REQS; ++i) begin    
        
        wire [MEM_ADDRW-1:0] block_addr = dcache_bus_in_if[i].req_data.addr[DCACHE_ADDR_WIDTH-1 -: MEM_ADDRW];
        wire bus_sel = (block_addr >= SMEM_START_B) && (block_addr < SMEM_END_B);

        VX_smem_switch #(
            .NUM_REQS     (2),
            .DATA_SIZE    (DCACHE_WORD_SIZE),
            .TAG_WIDTH    (DCACHE_TAG_WIDTH),
            .ARBITER      ("P"),
            .REQ_OUT_BUF  (2),
            .RSP_OUT_BUF  (2)
        ) smem_switch (
            .clk        (clk),
            .reset      (switch_reset),
            .bus_sel    (bus_sel),
            .bus_in_if  (dcache_bus_in_if[i]),
            .bus_out_if (switch_out_bus_if[i * 2 +: 2])
        );

        // output bus[0] goes to the dcache
        `ASSIGN_VX_MEM_BUS_IF (dcache_bus_out_if[i], switch_out_bus_if[i * 2 + 0]);

        // output bus[1] goes to the local memory
        `ASSIGN_VX_MEM_BUS_IF (smem_bus_if[i], switch_out_bus_if[i * 2 + 1]);
    end

    `RESET_RELAY (smem_reset, reset);
    
    VX_shared_mem #(
        .INSTANCE_ID($sformatf("core%0d-smem", CORE_ID)),
        .SIZE       (1 << `SMEM_LOG_SIZE),
        .NUM_REQS   (DCACHE_NUM_REQS),
        .NUM_BANKS  (`SMEM_NUM_BANKS),
        .WORD_SIZE  (DCACHE_WORD_SIZE),
        .ADDR_WIDTH (SMEM_ADDR_WIDTH),
        .UUID_WIDTH (`UUID_WIDTH), 
        .TAG_WIDTH  (DCACHE_TAG_WIDTH)
    ) shared_mem (        
        .clk        (clk),
        .reset      (smem_reset),

    `ifdef PERF_ENABLE
        .cache_perf (cache_perf),
    `endif
        .mem_bus_if (smem_bus_if)
    );

endmodule
