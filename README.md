# Banked Shared Memory Arbitrator

A synthesizable SystemVerilog arbitrator for a 16-bank shared memory, designed for use in a SIMT GPU / systolic array architecture. Resolves bank conflicts across 16 concurrent thread memory requests, with broadcast optimization for uniform reads and per-bank round-robin grant arbitration.

---

## Architecture Overview

<img width="1267" height="668" alt="image" src="https://github.com/user-attachments/assets/5896d8e3-44c2-4820-898b-d470b7ef1e1b" />



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

The Arbitrator contains a Pending request table for each bank and its registers. The requests get queued in this table(broadcasts, conflicts or mixed request type).
If a register in a bank is yet to be served, then its service flag is set with a corresponding Valid flag, when the request is served, its service flag is set to done and its valid flag is removed.

<img width="707" height="575" alt="image" src="https://github.com/user-attachments/assets/8cefb185-76ec-47f3-ab58-1e2317a2a019" />


### Example:
<img width="1882" height="562" alt="image" src="https://github.com/user-attachments/assets/f2368fa5-29d0-4cec-854e-223840ba31bb" />
(each entry has a corresponding service and valid flag)


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

### Example:
<img width="1650" height="137" alt="image" src="https://github.com/user-attachments/assets/fc0b0263-6457-4894-ac50-41266e965f4c" />


---

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

---

## Target Hardware

| Parameter | Value |
|-----------|-------|
| Banks | 16 |
| Data width | 16-bit |
| Threads | 16 |
| Address depth | 16 entries per bank |

## References
- NVIDIA TESLA:A UNIFIED GRAPHICS AND COMPUTING ARCHITECTURE

- Programming Massively Parallel Processors by Hwu and Kirk

