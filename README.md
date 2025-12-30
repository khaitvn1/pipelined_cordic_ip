# Pipelined CORDIC Trigonometric & Vector Processing IP Core

A synthesizable, parameterizable **CORDIC (COordinate Rotation DIgital Computer)** IP written in **SystemVerilog**. Built as an FPGA-friendly block with **ready/valid streaming**, **stallable pipelining (backpressure)**, and **numeric-quality knobs** (guard bits + optional gain compensation).

> Implemented on a **Digilent Basys 3 (Xilinx Artix-7)** at **100 MHz** and validated with real-time on-board results.

## Project Overview
This repository contains a CORDIC engine with two top-level modules:

- **Rotation mode — `cordic_rotator.sv`**  
  Computes **`cosine`** and **`sine`** by rotating an input vector `(x_start, y_start)` by a signed fixed-point angle `angle`.

- **Vectoring mode — `cordic_vectoring.sv`**  
  Computes **`theta = atan2(y, x)`** and **`mag = hypot(x, y)`** by iteratively driving `y -> 0`.

Both modes reuse the same pipelined micro-rotation stage (`cordic_stage.sv`), which makes the design easy to extend and keeps behavior consistent across modes.

---

## Key Features
### RTL Building Blocks
- **CORDIC pipeline stage — `cordic_stage.sv`**  
  - One micro-rotation per stage with a shift-by-`i` datapath. Supports **ROTATION** and **VECTORING** via a `MODE` parameter (shared stage RTL, different update equations).

- **Preprocessing**
  - **`cordic_preproc.sv` (rotation)**: full-range angle normalization + quadrant mapping so the iterative angle stays within the convergence range.
  - **`cordic_preproc_vec.sv` (vectoring)**: input normalization for correct **atan2** quadrant results (including `x < 0` correction via `±π` seeding).

- **Shared package — `cordic_pkg.sv`**
  - `atan` LUT constants
  - angle constants (`π`, `π/2`) in the chosen fixed-point format
  - gain compensation constant (`1/K`)

### Interfaces & Integration
- **Streaming handshake**:
  - Inputs: `in_valid/in_ready`
  - Outputs: `out_valid/out_ready`
- **Backpressure/stall support**:
  - If `out_valid=1` and `out_ready=0`, the core **stalls** and **holds all pipeline state** using clock-enable gating.
  - `in_ready` deasserts during stall so no inputs are accepted/dropped incorrectly.

### Numeric Quality Options
- **Guard bits — `GUARD`**  
  Widens internal X/Y datapath for headroom and reduced overflow risk.
- **Optional gain compensation — `GAIN_COMP`**
  - Rotation: post-scales `cos/sin` by `1/K` to preserve amplitude
  - Vectoring: post-scales `mag` by `1/K` to return true `hypot(x, y)`
- Parameterized:
  - `XY_W` (data width)`ANGLE_W` (angle width), `ITER` (iteration count), `GUARD`, `GAIN_COMP`

### Full-Range Handling
- **Rotation:** quadrant-based normalization for full **0 to 2π** angle coverage  
- **Vectoring:** correct **atan2** behavior across all quadrants via right-half-plane normalization and `z0` seeding

---

## Repository Structure
```
├── sim/
│ ├── Include/
│ │ └── cordic.include # file list / include setup (tool dependent)
│ └── Testbench/ # UVM verification environment
│   ├── agent/ # driver, monitor, sequencer
│   ├── env/ # env + scoreboard (with golden models to test outputs)
│   ├── sequences/ # directed + randomized sequences (rotator/vectoring/pipeline)
│   ├── tb/ # top-level testbench (interfaces, clock/reset, etc.)
│   ├── tests/ # UVM tests
│   ├── MakefileUVM # make targets for simulation runs
│   └── link_files_uvm.py # helper script to link/collect sources
│
├── src/
│ ├── constraint/ # constraints (used for FPGA implementation)
│ ├── interfaces/ # SystemVerilog interfaces (ready/valid, etc.)
│ ├── packages/ # cordic_pkg that contains shared types/constants
│ ├── rtl/ # synthesizable RTL sources (rotator/vectoring/stages/preproc)
│ └── script/ # project's TCL script (create/build entire project flow in Xilinx Vivado)
│
├── LICENSE
├── .gitignore
├── README.md
└── README_UVM.md
```

---

## Architecture Details
### How the Pipeline is Created
This is a real pipeline because each stage registers its outputs and stages are wired in sequence:

- Each `cordic_stage` has an `always_ff` register boundary.
- A `generate for` loop creates `ITER` stages and connects stage `i -> i+1`.

Data flows like this: (preproc regs) → stage0 regs → stage1 regs -> … -> stage(ITER-1) regs -> outputs

With `ITER=16`, the stage index is `i = 0..15` (16 total stages).

The tap arrays are sized `[0:ITER]` because there are **ITER+1 pipeline boundaries**:
- `x_pipe[0]` is the preprocessed input
- `x_pipe[ITER]` is the final stage output

### Backpressure / Stall Behavior
- `stall = out_valid && !out_ready`
- When stalled, all pipeline registers are gated with `ce = !stall`
- Outputs remain stable until the downstream consumer asserts `out_ready`

### Shared Stage for Two Modes
The same `cordic_stage` module supports both modes by switching the direction selection and update equations:
- **Rotation:** direction derived from `sign(z)` (drives residual angle -> 0)
- **Vectoring:** direction derived from `sign(y)` (drives y -> 0)

---

## Functional Verification

### UVM Verification Environment
Functional verification is implemented with a constrained-random **UVM** testbench that includes:
- Directed tests for known angles/quadrants and axis cases
- Constrained-random stimulus for broad coverage
- Randomized backpressure (`out_ready` toggling) to stress stall/hold behavior
- Scoreboard golden models using `sin/cos/atan2/sqrt` reference math

### What is Verified
- `sin/cos` correctness across the full angle range (including quadrant boundaries)
- `atan2` correctness across all quadrants (including `x < 0` and axis cases)
- magnitude correctness with and without gain compensation
- ready/valid protocol correctness under stalls (no drops, stable outputs while stalled)

See **`README_UVM.md`** for more details and how to run the tests.

---

## Performance Metrics

Implemented on **Digilent Basys 3 (Xilinx Artix-7)** using Xillinx Vivado Design Suite:

- **Throughput:** 1 sample/cycle (after pipeline fill, when not stalled)
- **Clock:** 100 MHz
- **Resources (typical):**
  - LUTs: ~1,000
  - FFs: ~1,200
  - DSPs: 0
  - BRAMs: 0

> Resource use vary with `XY_W`, `ITER`, `GUARD`, and whether gain compensation is enabled.

---

## Practical Applications

This CORDIC IP is handy anywhere you need **trig**, **vector magnitude**, or **angle extraction** in hardware with predictable latency and clean streaming integration. While modern FPGAs have DSP blocks, CORDIC still earns its spot when you **don’t want to waste DSPs** on sin/cos or atan2—especially in designs where DSPs are reserved for filters, MAC-heavy kernels, or ML workloads.

Examples:
- **Digital communications / SDR**
  - NCO/LO generation (sin/cos)
  - I/Q rotation for phase and frequency correction
  - Polar conversion (I/Q -> magnitude/phase) for demodulation and tracking loops

- **Motor control / power electronics**
  - Field-oriented control (FOC) transforms (sin/cos rotations)
  - Encoder/resolver processing (atan2 + magnitude)

- **Robotics / navigation**
  - Convert vectors to heading + speed (atan2 + magnitude)
  - Sensor processing pipelines that need repeated angle/magnitude ops

- **Imaging / computer vision**
  - Gradient magnitude + orientation (atan2) for feature extraction
 
---

## Known Limitations
- **Output truncation:** final outputs are typically truncated to `XY_W`; rounding/saturation is optional (and can be improved).
- **LUT depth:** `ITER` must not exceed the number of entries in `atan_lut()` unless the LUT is extended/generated.
- **Scaling convention:**
  - `GAIN_COMP=0`: outputs include CORDIC gain `K`
  - `GAIN_COMP=1`: post-scaled by `1/K` to match expected amplitude/magnitude

---

## Future Improvements
- Add **round-to-nearest + saturation** on final output formatting
- Auto-generate the `atan` LUT for arbitrary `ITER`
- Expand into **formal verification** using **SystemVerilog Assertions (SVA)** for handshake + stall
