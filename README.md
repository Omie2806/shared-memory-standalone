# Banked Shared Memory Arbitrator

A synthesizable SystemVerilog arbitrator for a 16-bank shared memory, designed for use in a SIMT GPU / systolic array architecture. Resolves bank conflicts across 16 concurrent thread memory requests, with broadcast optimization for uniform reads and per-bank round-robin grant arbitration.

---

## Architecture Overview

<img width="1136" height="696" alt="image" src="https://github.com/user-attachments/assets/33be1ee1-22b8-47a4-9e89-dab7ffe964c1" />


### Address Decomposition

Each thread's address is split using low-order interleaved banking:

```
addr[15:0]
  [3:0]  → bank index   (selects one of 16 banks)
  [7:4]  → depth index  (row within the selected bank)
```

This layout distributes sequential addresses across banks, minimizing conflicts for stride 1 access patterns.

---

## Module Interface

```systemverilog
module arbitrator #(
    parameter BANKS             = 16,
    parameter DW                = 16,
    parameter NUMBER_OF_THREADS = 16,
    parameter ADDR_DEPTH        = 16
) (
    input  logic                          clk,
    input  logic                          reset,
    input  logic                          matmul,
    input  logic                          mem_write,
    input  logic                          mem_req,
    input  logic [NUMBER_OF_THREADS-1:0]  active_mask,
    input  logic [ADDR_DEPTH-1:0]         addr     [0:NUMBER_OF_THREADS-1],
    input  logic [DW-1:0]                 data_in  [0:NUMBER_OF_THREADS-1],
    output logic [DW-1:0]                 data_out [0:NUMBER_OF_THREADS-1],
    output logic                          stall
);
```

| Signal        | Direction | Description |
|---------------|-----------|-------------|
| `clk`         | in  | System clock |
| `reset`       | in  | Synchronous active-high reset |
| `matmul`      | in  | Passed through to memory banks; enables systolic accumulate mode |
| `mem_write`   | in  | High = write, Low = read |
| `mem_req`     | in  | Initiates a memory transaction this cycle |
| `active_mask` | in  | Per-thread enable; inactive threads are ignored by arbitration |
| `addr`        | in  | 16-bit addresses from each thread |
| `data_in`     | in  | Write data from each thread |
| `data_out`    | out | Read data returned to each thread |
| `stall`       | out | Asserted when pending requests remain unserved |

---

## Conflict Resolution

When multiple threads target the same bank in a single cycle, only one is granted per cycle. The rest are tracked in a pending request register (`bank_request`) and replayed in subsequent cycles until all are served. `stall` remains asserted until all pending requests are cleared.

```
Cycle 0: Threads 0,1,2,3 all request Bank 1
         → Grant thread 0, pending = {1,2,3}

Cycle 1: pending = {1,2,3}
         → Grant thread 1, pending = {2,3}

Cycle 2: pending = {2,3}
         → Grant thread 2, pending = {3}

Cycle 3: pending = {3}
         → Grant thread 3, pending = {}
         → stall deasserted
```

---

## Broadcast Optimization

When multiple threads issue a read to the **same bank and same depth address**, this is detected as a broadcast read. A single bank access serves all matching threads simultaneously, rather than serializing them. This is the GPU equivalent of a uniform/splat load(common in weight broadcasts during matrix multiply).
*Memory Writes are not broadcasted due to the uncertainity of the winning thread.*

---

## Testbench Coverage

`tb_memory_arbitrator.sv` covers the following scenarios:

| Test | Scenario |
|------|----------|
| 1 | Write with inter-bank conflicts (threads 1, 2, 3 target same banks) |
| 2 | Cross-read: thread 1 reads address written by thread 3, and vice versa |
| 3 | Conflict-free write across all 16 banks |
| 4 | Cross-bank read (thread 2 reads thread 4's address) |
| 5 | All 16 threads target a single bank (worst-case conflict, 16 stall cycles) |
| 6 | Read back test 5's data(first 4 threads cause broadcasting rest will cause conflicts in banks 2, 3 and 4)|
| 7 | 4-way conflicts across 4 banks simultaneously |
| 8 | Broadcast read: 4 threads read the same address in the same bank |

---

## Integration Context

This module is part of a larger SIMT GPU and systolic array implementation

- 4 warps × 16 lanes SIMT core
- IPDOM-based branch divergence stack
- Dual-mode 4×4 systolic array (MATMUL + elementwise via `op_mode`)
- The systolic array holds unconditional priority on the shared memory port; SIMD stalls are absorbed by warp scheduling(probably access policy will change)

---

## Known Limitations / Work in Progress

- Arbitration is currently fixed-priority (lowest thread index wins per bank). True round-robin with aging is not yet implemented.
- Pending mask replay adds one cycle of latency per conflict level; no out-of-order completion.
- Broadcast detection requires matching both bank and depth address; partial overlap is not tested yet.
- `stall` is combinationally derived from `bank_request`.


---

## Target Hardware

| Parameter | Value |
|-----------|-------|
| Banks | 16 |
| Data width | 16-bit |
| Threads | 16 |
| Address depth | 16 entries per bank |
