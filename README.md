# 4-bit Array Multiplier: RTL to GDSII (SKY130)

| Name | Roll number |
|---|---|
| Nilavra Ghosh | 2023102006 |
| Prakhar Gupta | 2023112019 |

Example used in Part A: A = 6 + 5 = **11** (last digit of 2023102006, Nilavra Ghosh), B = **7**, so A × B = 77.

**Environment:** IIC-OSIC-TOOLS Docker image `hpretl/iic-osic-tools:latest` (release 2026.10) with Yosys 0.70, OpenSTA 3.1.0, LibreLane v3.1.0.dev3, Icarus Verilog 14.0 and KLayout. The RTL simulation in Part A was also run with Icarus Verilog 11.0 on the Ubuntu host, with identical results. Technology: SKY130A, `sky130_fd_sc_hd`, typical corner `tt_025C_1v80` for Parts B and C.

All commands are run from the repository root unless a step says otherwise. Inside the container the repository is at `/foss/designs/DVD-2023102006-2023112019`.

## Repository layout

```
README.md
rtl/full_adder.v           full adder (assign statements only)
rtl/mult_array.v           4x4 array multiplier, 12 full_adder instances, 16 flip-flops
tb/tb_mult.v               exhaustive self-checking testbench (256 vectors)
synth/synth.tcl            Yosys script
synth/mult_array_netlist.v gate-level netlist (generated)
synth/mult_array_stat.rpt  cell and area report (generated)
sta/sta.tcl                OpenSTA script
sta/mult_array_timing.rpt  critical path report at T = 10 ns (generated)
pnr/config.json            LibreLane configuration
pnr/metrics.json           metrics of the final LibreLane run
pnr/mult_array.gds         final layout
report/report.pdf          report with tables, screenshots and answers
```

## Part A: RTL design and verification

```bash
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim
gtkwave mult.vcd
```

Result: `PASS: 256 vectors checked, 0 errors`

The 11 × 7 example in `mult.vcd`: `a = 11, b = 7` are applied at 3680 ns (falling edge), registered into `a_r, b_r` at rising edge 1 (3685 ns), and `p = 77` is registered at rising edge 2 (3695 ns). Latency: 2 clock cycles.

Error-injection test (the full adder's sum is broken to `a ^ b`, then restored):

```bash
sed -i 's/assign sum  = a ^ b ^ cin;/assign sum  = a ^ b;/' rtl/full_adder.v
grep "assign sum" rtl/full_adder.v
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim
git checkout rtl/full_adder.v
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim
```

Result with the bug: `FAIL: 256 vectors checked, 95 errors` (first mismatches: `a=3 b=3 expected=9 got=5`, `a=3 b=6 expected=18 got=10`, `a=3 b=7 expected=21 got=9`). After `git checkout` the testbench prints `PASS: 256 vectors checked, 0 errors` again.

## Part B: Logic synthesis (container)

```bash
yosys -c synth/synth.tcl
cat synth/mult_array_stat.rpt
grep -c sky130_fd_sc_hd__dfrtp synth/mult_array_netlist.v      # 16

CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls \
  tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v
vvp gls
```

Results: 73 cells (16 `dfrtp_1` flip-flops), total area 805.773 µm², flip-flop area 400.384 µm² (49.69 %). Gate-level simulation: `PASS: 256 vectors checked, 0 errors`.

The gate-level run overwrites `mult.vcd`; re-run `vvp sim` afterwards to get the RTL waveform back.

## Part C: Static timing analysis (container)

```bash
sta -no_splash sta/sta.tcl             # T = 10 ns
T=2.60 sta -no_splash sta/sta.tcl      # T = Tmin
T=2.59 sta -no_splash sta/sta.tcl      # one step below Tmin
sta -no_splash sta/sta.tcl             # re-run at T = 10 ns so the committed report is the T = 10 ns one
```

`sta.tcl` reads the period from the environment variable `T` and defaults to 10 ns.

| Clock period | Worst setup slack |
|---|---|
| 10.00 ns | +7.404 ns (printed as 7.40) |
| 2.60 ns | +0.004 ns (printed as 0.00) |
| 2.59 ns | −0.006 ns (printed as −0.01) |

Tmin = 10 − 7.404 = 2.596 ≈ **2.60 ns**, Fmax = 1000 / 2.60 = **384.6 MHz**. Critical path: `b_r[0]` (input register) → `p[6]` (output register).

## Part D: Place and route with LibreLane (container)

The container defaults to the IHP PDK, so the SKY130 PDK and cell library are selected explicitly.

```bash
cd pnr
export PDK=sky130A STD_CELL_LIBRARY=sky130_fd_sc_hd
librelane --manual-pdk --pdk-root $PDK_ROOT -p sky130A -s sky130_fd_sc_hd config.json 2>&1 | tee run1.log
# setup failed: CLOCK_PERIOD += 0.5 ns in config.json, run again (run2.log ... run8.log)
cp runs/RUN_2026-10-22_19-36-08/final/metrics.json .
cp runs/RUN_2026-10-22_19-36-08/final/gds/mult_array.gds .
klayout -nn $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyt \
        -l  $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp mult_array.gds
```

The starting CLOCK_PERIOD was 1.2 × Tmin = 1.2 × 2.60 = 3.12 ns, rounded up to 3.5 ns. Every attempt:

| Attempt | CLOCK_PERIOD (ns) | Run folder | Setup WS (ns) | DRC | LVS | Result |
|---|---|---|---|---|---|---|
| 1 | 3.5 | RUN_2026-10-22_19-25-27 | −2.144 | 0 | 0 | FAIL (setup, ss corner) |
| 2 | 4.0 | RUN_2026-10-22_19-27-25 | −1.644 | 0 | 0 | FAIL (setup, ss corner) |
| 3 | 4.5 | RUN_2026-10-22_19-28-52 | −1.144 | 0 | 0 | FAIL (setup, ss corner) |
| 4 | 5.0 | RUN_2026-10-22_19-30-19 | −0.644 | 0 | 0 | FAIL (setup, ss corner) |
| 5 | 5.5 | RUN_2026-10-22_19-31-47 | −0.144 | 0 | 0 | FAIL (setup, ss corner) |
| 6 | 6.0 | RUN_2026-10-22_19-33-14 | −0.082 | 0 | 0 | FAIL (setup, ss corner) |
| 7 | 6.5 | RUN_2026-10-22_19-34-43 | −0.165 | 0 | 0 | FAIL (setup, ss corner) |
| 8 | **7.0** | RUN_2026-10-22_19-36-08 | **+0.335** | 0 | 0 | **PASS** |

Setup slack is `timing__setup__ws`, the worst over all corners. The typical corner (tt) passed in every run; every failure was at the slow corner (ss, 100 °C, 1.60 V). Final run: 0 DRC errors (Magic, KLayout and router), 0 LVS errors, setup slack +0.335 ns, hold slack +0.141 ns. Post-route Fmax = 1000 / (7.0 − 0.335) = **150.0 MHz**.

Outside the official +0.5 ns procedure, periods of 6.1–6.9 ns were also tried. Slack is not monotonic below 6.6 ns because the tool re-optimises for each target. From 6.7 ns (+0.035 ns) upward it rises exactly with the period, so the ss-corner path delay is about 6.665 ns and Fmax is 150 MHz either way. 7.0 ns is kept because it follows the assignment's rule.

LibreLane prints 494 Verilator `TIMESCALEMOD` lint warnings. All of them come from LibreLane-generated cell and I/O stub files: none come from our RTL, and there are 0 lint errors.
