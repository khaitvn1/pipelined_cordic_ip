# Pipelined CORDIC Trigonometric & Vector Processing IP — UVM Testbench Documentation

## Testbench Overview

This document describes the **UVM verification environment** used to validate the math (ROT & VEC) calculations,
ready/valid handshakes and pipeline stall behaviors of the **CORDIC IP**.

The CORDIC engine supports two operating modes:

- **Rotation mode (`CORDIC_ROT`)**  
  Inputs: `(x_in, y_in, z_in=angle)` -> Outputs: `(cos_out, sin_out)`
- **Vectoring mode (`CORDIC_VEC`)**  
  Inputs: `(x_in, y_in)` -> Outputs: `(mag_out, theta_out)`

The UVM testbench validates:
- Functional correctness vs. a math golden model (with tolerances)
- Proper **ready/valid** handshake behavior
- **Pipeline stall** behavior via `out_ready` backpressure (exercises `in_ready`, `ce`)
- Coverage collection (toggle/code/branch coverage) in Cadence Xcelium

### Key Features
- **Mode-aware verification** (rotation + vectoring)
- **Golden-model scoreboard** (sin/cos + atan2/magnitude)
- **Gain compensation support** (adjustable DUT parameter and scoreboard config)
- **Backpressure + stall coverage** to toggle control/enable signals

---

## Important Component Details

### 1) UVM Test (`cordic_*_test`)
- Selects which sequences to run (directed, random, backpressure)
- Controls objections and overall runtime
- Recommended approach: run **ROT** and **VEC** as separate sims, then **merge coverage**

### 2) UVM Environment (`cordic_env`)
- Instantiates the agent and scoreboard
- Connects monitor analysis output into the scoreboard’s analysis export

### 3) UVM Agent (`cordic_agent`)
- Creates and connects:
  - `cordic_driver`
  - `cordic_monitor`
  - `cordic_sequencer`
- Owns the virtual interface handle passed via `uvm_config_db`

### 4) UVM Driver (`cordic_driver`)
- Implements streaming valid/ready driving:
  - Asserts `in_valid` with `(x_in, y_in, z_in)`
  - Waits until `in_ready` to complete the handshake
- Generates **backpressure** on `out_ready` using `cordic_cfg` knobs:
  - `READY_ALWAYS`: `out_ready=1` (no stalls)
  - `READY_RANDOM`: `out_ready` randomly deasserted
  - `READY_BURST`: periodic multi-cycle low bursts
- Backpressure is the primary way to toggle:
  - `out_ready`, `in_ready`, internal stall logic, and pipeline `ce`

### 5) UVM Monitor (`cordic_monitor`)
- Observes accepted **inputs** on `(in_valid && in_ready)`
- Observes accepted **outputs** on `(out_valid && out_ready)`
- Matches outputs to the oldest input (in-order queue)
- Emits a single `cordic_seq_item` to the scoreboard containing:
  - captured input fields
  - captured output fields

### 6) UVM Scoreboard (`cordic_sb`)
Golden model checks with configurable tolerances:

- **Rotation mode**
  - `cos_out ≈ (x*cos(z) - y*sin(z))`
  - `sin_out ≈ (x*sin(z) + y*cos(z))`
- **Vectoring mode**
  - `mag_out ≈ sqrt(x^2 + y^2)`
  - `theta_out ≈ atan2(y, x)` in the DUT’s 32-bit angle format

**Gain compensation**
- DUT uses a compile-time parameter `GAIN_COMP`
- Scoreboard uses `cfg.gain_comp`
- These must match or the scoreboard will see a scale mismatch and fail immediately.

### 7) Transaction Item (`cordic_seq_item`)
Carries:
- Inputs: `x_in`, `y_in`, `z_in`
- Outputs: `cos_out`, `sin_out`, `mag_out`, `theta_out`

---

## Verification Flow

**Step 1: Build/Connect**
1. `cordic_tb_top` builds clock/reset and sets `uvm_config_db` entries
2. Test builds the env -> env builds agent + scoreboard

**Step 2: Stimulus**
1. Sequence generates items
2. Driver performs input handshakes
3. Driver also drives `out_ready` behavior (backpressure modes)

**Step 3: Collection + Checking**
1. Monitor records accepted inputs and queues them
2. Monitor pairs accepted outputs with oldest queued input
3. Monitor writes the completed transaction into the scoreboard
4. Scoreboard computes expected results and checks within tolerance
5. End-of-test report summarizes pass/fail counts

---

## Sequences & Tests
This testbench uses a focused sequence library to exercise functional correctness with direct/constraint-random test sequences, 
and pipeline robustness:

All sequences are defined in ``cordic_seq_lib.sv`` and are coordinated by a single top-level test for simplicity.

Top-Level Test: ``all_cordic_test`` is the main entry point selected via ``+UVM_TESTNAME=all_cordic_test``.

It runs multiple sequences back-to-back to provide both correctness and coverage in a single regression:
  - Directed (with corner-case) sequences first
  - Constrained-random sequences to raise coverage
  - Backpressure sequences to test the pipeline
  - Intended to be run once per mode (ROT and VEC), then coverage merged.

### Directed Sequence
- ``rot_directed_seq`` and ``vec_directed_seq``:
  - Deterministic corner-case stimulus
  - No backpressure by default (clean functional path)
Covered cases:
- Rotation mode:
  - angles near 0, ±π/2, ±π (±1 LSB around boundaries)
  - axis-aligned vectors: (1,0), (0,1), (-1,0), (0,-1)
- Vectoring mode:
  - all four quadrants
  - x=0 / y=0 axis cases
  - small-magnitude vectors (atan2 sensitivity)

### Constrained-Random Sequence
- ``rot_random_seq`` and ``vec_random_seq``:
  - Randomizes x_in, y_in, and z_in (rotation mode)
  - Randomizes x_in, y_in, and ignore z_in (vectoring mode)
  - Configurable transaction count and input constraints

### Backpressure/Stall Stress Sequence
- `cordic_backpressure_seq`
  - Sends a transactions of driven via cordic_cfg (modes, item counts, etc.)
  - Enables READY_ALWAYS/READY_BURST/READY_RANDOM modes in `cfg`
    - READY_ALWAYS: no stalls
    - READY_RANDOM: random single-cycle stalls
    - READY_BURST: multi-cycle backpressure bursts
  - Forces stalls -> toggles `out_ready`, `in_ready`, and internal `ce`

---

## Usage

This repo expects:
- `cordic_tb_top.sv` instantiates the DUT (`cordic_dut_uvm`) and interface
- The test is selected via `+UVM_TESTNAME=<test_name>` in the `MakefileUVM` file. For this testbench, I have added all of the sequences under `all_cordic_test`, so in `Makefile`: `+UVM_TESTNAME=all_cordic_test`
- You need to have a Cadence license to proceed, I'm using SiliconJacket's, thank you :). Then clone the repo first, then follow these steps to run the testbench:

### 1. Environment Setup:
```bash
# Switch to sim folder
cd sim

# Switch to tcsh shell
tcsh 
```

### 2. Run Simulation:
```bash
# Compile and simulate the testbench
make xrun
```

### 3. View Results:
```bash
# View waveform simulation in SimVision
make simvision

# View code coverage in Xcelium
make coverage

# Remove the compiled results from the previous xrun
make clean
```

### Test Configuration
`cordic_cfg` is placed into `uvm_config_db` and used by:
- driver (ready/backpressure behavior)
- scoreboard (mode/gain/tolerances)
- sequences (override ready behavior for backpressure tests)

Core knobs:
- `cfg.mode` = `CORDIC_ROT` or `CORDIC_VEC`
- `cfg.gain_comp` = must match DUT parameter `GAIN_COMP`
- `cfg.tol_xy_lsb` / `cfg.tol_theta_lsb`

Backpressure knobs:
- `cfg.ready_mode`
- `cfg.ready_low_pct`
- `cfg.burst_start_pct`
- `cfg.burst_low_min`, `cfg.burst_low_max`

### Adding New Sequences/Tests
1. Create a new sequence class in `cordic_seq_lib.sv`
2. Register it with `` `uvm_object_utils(...) ``
3. Start it from:
   - a test’s `run_phase`, or
   - as a `default_sequence` on the sequencer path

---

## Important Notes

### 1) Run both modes and merge coverage
Rotation and vectoring drive different outputs and datapaths. A single-mode run will naturally miss toggles in the other mode.

Recommended:  
- Run `MODE=ROT` sim -> collect coverage  
- Run `MODE=VEC` sim -> collect coverage  
- Merge results in Cadence IMC/Xcelium coverage flow

### 2) Backpressure is used to raise toggling coverage
If `out_ready` is stuck high:
- no stalls occur
- `in_ready` rarely toggles
- pipeline `ce` rarely toggles

Enable backpressure to meaningfully exercise stall gating logic.

### 3) Some signals may be constant by design
If a signal like `atan_i` is derived from a **generate-time constant stage index**, it will be constant per stage and may never toggle. This is normal; consider excluding such nets from toggle coverage metrics.

---

## Summary

**Top files**
- `cordic_tb_top.sv` — clock/reset, DUT, config_db, wave dump
- `cordic_if.sv` — interface + clocking blocks + modports

**UVM components**
- `cordic_tb_pkg.sv` — cfg enums/fields (mode, backpressure, tolerances)
- `cordic_agent_pkg.sv`, `cordic_agent.sv` — agent + connections
- `cordic_env.sv` — env + scoreboard hookup
- `cordic_driver.sv` — handshake driving + out_ready backpressure generator
- `cordic_monitor.sv` — input/output sampling + transaction pairing
- `cordic_sb.sv` — golden model + tolerance checks
- `cordic_seq_item.sv` — transaction item
- `cordic_seq_lib.sv`, `cordic_sequence.svh` — directed/random/backpressure sequences
- `cordic_test_lib.sv`, `cordic_base_test.svh` — test classes

---