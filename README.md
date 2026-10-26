# 4-bit Array Multiplier: RTL to GDSII (SKY130)

| Name | Roll number |
|---|---|
| Nilavra Ghosh | 2023102006 |
| Prakhar Gupta | 2023112019 |

Example used in Part A: A = 6 + 5 = **11** (last digit of 2023102006, Nilavra Ghosh), B = **7**, so A × B = 77.

**Environment:** IIC-OSIC-TOOLS Docker image `hpretl/iic-osic-tools:latest` (release 2026.10) with Yosys 0.70, OpenSTA 3.1.0, LibreLane v3.1.0.dev3, Icarus Verilog 14.0 and KLayout. The original testbench was also run with Icarus Verilog 11.0 on the Ubuntu host, with identical results; the revised testbench (latency and reset checks) was run only in the container with Icarus Verilog 14.0. Technology: SKY130A, `sky130_fd_sc_hd`, typical corner `tt_025C_1v80` for Parts B and C.

All commands are run from the repository root unless a step says otherwise. Inside the container the repository is at `/foss/designs/DVD-2023102006-2023112019`.

Tool check (container, Section 4.2 of the guide):

```bash
iverilog -V | head -1      # Icarus Verilog version 14.0 (devel)
yosys -V                   # Yosys 0.70
sta -version               # 3.1.0
echo $PDK_ROOT $PDK        # the container defaults to IHP; SKY130 is selected explicitly below
```

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

The testbench applies the 256 vectors back to back (one new `a, b` on every falling edge) and checks every cycle that `p` equals the product of the inputs applied two rising edges earlier, so a wrong latency or a design that cannot take one input per cycle fails. It also checks reset: `p = 0` during the initial reset with `a = b = 15` applied, the first result after release is 0 (`a_r, b_r` cleared), a mid-run reset asserted between clock edges clears `p` before the next edge (asynchronous), and the pipeline recovers (0, then 3 × 5 = 15). Mismatch lines name the check that failed.

The hand-worked examples in `mult.vcd` (markers in the report's waveform figure):

| Example | Inputs applied (falling edge) | Rising edge 1: `a_r, b_r` | Rising edge 2: `p` |
|---|---|---|---|
| 11 × 7 (Nilavra Ghosh, 2023102006: A = 6 + 5) | 1850 ns | 1855 ns | 1865 ns, `p = 77` |
| 14 × 7 (Prakhar Gupta, 2023112019: A = 9 + 5) | 2330 ns | 2335 ns | 2345 ns, `p = 98` |

Latency: 2 clock cycles; throughput: one result per cycle.

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

Result with the bug: `FAIL: 256 vectors checked, 96 errors`: 95 of the 256 products are wrong, plus the extra 15 × 15 check before the mid-run reset (first mismatches: `a=3 b=3 expected=9 got=5`, `a=3 b=6 expected=18 got=10`, `a=3 b=7 expected=21 got=9`). After `git checkout` the testbench prints `PASS: 256 vectors checked, 0 errors` again.

Testbench strength check (not required by the assignment): five more faulty copies of `mult_array.v` are written to `/tmp/mut` (never committed) and simulated:

```bash
mkdir -p /tmp/mut
sed 's/a_r & {4{b_r\[\([0-3]\)\]}}/a \& {4{b[\1]}}/' rtl/mult_array.v > /tmp/mut/latency1.v
sed -e 's/reg \[3:0\] a_r, b_r;/reg [3:0] a_r, b_r; reg [7:0] p_d;/' -e "s/p   <= 8'd0;/p   <= 8'd0; p_d <= 8'd0;/" -e 's/p   <= prod;/p_d <= prod; p <= p_d;/' rtl/mult_array.v > /tmp/mut/latency3.v
sed -e "s/a_r <= 4'd0;//" -e "s/b_r <= 4'd0;//" rtl/mult_array.v > /tmp/mut/noreset_in.v
sed 's/posedge clk or negedge rst_n/posedge clk/' rtl/mult_array.v > /tmp/mut/syncreset.v
sed "s/p   <= 8'd0;/p   <= 8'd255;/" rtl/mult_array.v > /tmp/mut/reset255.v
for m in latency1 latency3 noreset_in syncreset reset255; do
  iverilog -g2012 -o /tmp/mut/sim_$m tb/tb_mult.v rtl/full_adder.v /tmp/mut/$m.v && echo "$m: $(vvp -n /tmp/mut/sim_$m | grep -E '^(PASS|FAIL)')"
done
```

All five fail: latency 1 (inputs not registered) 240 errors, latency 3 (extra output register) 240 errors, `a_r, b_r` not reset 2 errors, synchronous instead of asynchronous reset 1 error, `p` reset to 255 4 errors.

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

Structural check that the inputs and the output are registered (the testbench cannot tell a registered output from a combinational one fed by two register stages):

```bash
grep -c 'sky130_fd_sc_hd__dfrtp_1 ' synth/mult_array_netlist.v                                   # 16 flip-flops
grep -A6 'sky130_fd_sc_hd__dfrtp_1 ' synth/mult_array_netlist.v | grep -c '\.Q(p\['               # 8: every p bit is a flip-flop Q
grep -cE '\.(X|Y)\(p\[' synth/mult_array_netlist.v                                              # 0: no gate drives p
grep -A6 'sky130_fd_sc_hd__dfrtp_1 ' synth/mult_array_netlist.v | grep -cE '\.D\((a|b)\['        # 8: every a/b bit is a flip-flop D
grep -cE '\.[A-Z0-9_]+\((a|b)\[' synth/mult_array_netlist.v                                     # 8: and a/b go nowhere else
```

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
# (the run*.log files and runs/ are not in the repository; runs/ is too large)
cp runs/RUN_2026-10-22_19-36-08/final/metrics.json .
cp runs/RUN_2026-10-22_19-36-08/final/gds/mult_array.gds .
klayout -nn $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyt \
        -l  $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp mult_array.gds
```

The starting CLOCK_PERIOD was 1.2 × Tmin = 1.2 × 2.60 = 3.12 ns, rounded up to 3.5 ns. Every attempt:

| Attempt | CLOCK_PERIOD (ns) | Run folder | Setup WS, all corners (ns) | Setup WS, worst tt (ns) | DRC | LVS | Result |
|---|---|---|---|---|---|---|---|
| 1 | 3.5 | RUN_2026-10-22_19-25-27 | −2.144 | +0.568 | 0 | 0 | tt PASS, ss FAIL |
| 2 | 4.0 | RUN_2026-10-22_19-27-25 | −1.644 | +1.068 | 0 | 0 | tt PASS, ss FAIL |
| 3 | 4.5 | RUN_2026-10-22_19-28-52 | −1.144 | +1.568 | 0 | 0 | tt PASS, ss FAIL |
| 4 | 5.0 | RUN_2026-10-22_19-30-19 | −0.644 | +2.068 | 0 | 0 | tt PASS, ss FAIL |
| 5 | 5.5 | RUN_2026-10-22_19-31-47 | −0.144 | +2.568 | 0 | 0 | tt PASS, ss FAIL |
| 6 | 6.0 | RUN_2026-10-22_19-33-14 | −0.082 | +2.883 | 0 | 0 | tt PASS, ss FAIL |
| 7 | 6.5 | RUN_2026-10-22_19-34-43 | −0.165 | +3.164 | 0 | 0 | tt PASS, ss FAIL |
| 8 | **7.0** | RUN_2026-10-22_19-36-08 | **+0.335** | +3.664 | 0 | 0 | **PASS, all corners** |

LibreLane signs off at nine corners (tt, ss, ff × nominal, minimum, maximum wire parasitics); `timing__setup__ws` is the worst of all nine, and "worst tt" is the worst of the three tt corners. Every failure was at the slow corner (ss, 100 °C, 1.60 V).

**Which period is the result.** Both are reported. Run 1 (3.5 ns) is the value the assignment prescribes (1.2 × Tmin rounded up) and already meets setup at the typical corner, the corner used in Part C: post-route Fmax at tt = 1000 / (3.5 − 0.568) = 341.1 MHz. To get there the resizer upsized 19 cells and added 3 setup buffers and 1 hold buffer; runs 1 and 8 start from the same synthesized netlist, and run 8 needed no timing repair. Run 8 (7.0 ns) is the submitted configuration, the first run that meets setup at every corner: 0 DRC errors (Magic, KLayout and router), 0 LVS errors (Netgen: circuits match uniquely), setup slack +0.335 ns, hold slack +0.141 ns, post-route Fmax = 1000 / (7.0 − 0.335) = **150.0 MHz** (299.8 MHz at tt). `pnr/config.json`, `pnr/metrics.json` and `pnr/mult_array.gds` are run 8's files; `metrics.json` and the GDS are byte-identical to that run's `final/` folder (same MD5).

The ss-corner path delay is not a fixed number: it was 5.644 ns in runs 1–5, 6.082 ns in run 6 and 6.665 ns in runs 7–8, because the resizer works harder when the target period is tighter.

Periods of 6.1–6.9 ns were also tried outside the +0.5 ns procedure. Their run folders and logs were not kept, so these results cannot be re-checked; the numbers below are copied from our notes only (commit 5700100, `report_assets/part_d_notes.md`): 6.1 −0.179, 6.2 −0.216, 6.3 −0.116, 6.4 −0.016, 6.6 −0.065, 6.7 +0.035, 6.8 +0.135, 6.9 +0.235 ns. They do not change the submitted result.

Post-route gate-level simulation of the final netlist (from the local `runs/` folder):

```bash
CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls \
  tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v \
  pnr/runs/RUN_2026-10-22_19-36-08/final/nl/mult_array.nl.v
vvp gls          # PASS: 256 vectors checked, 0 errors
```

Both gate-level simulations are functional (`-DFUNCTIONAL`: logic cells have zero delay, flip-flops a 1 ns unit delay), so they check behaviour, not timing; timing is checked by STA.

**Pre-route vs post-route timing.** OpenSTA was re-run on the final netlist (`final/nl`) with the tt and ss libraries, adding one effect at a time, with Tmin = 7.0 − worst setup slack (report, Table 7). At tt: Part C constraints 2.596 ns → LibreLane netlist 2.644 → + extracted wire RC (`final/spef/nom`) 2.901 → + propagated clock 2.910 → + 0.25 ns clock uncertainty 3.160 → + ±5 % derate 3.313 → full LibreLane SDC (`final/sdc/mult_array.sdc`, its generic fallback SDC, since no `PNR_SDC_FILE` was set) 3.313 → max parasitics 3.336 ns (= LibreLane's max_tt slack +3.664 ns). The same steps at ss give 5.480 → 6.665 ns (= max_ss slack +0.335 ns). Physical implementation (netlist, wires, clock tree) costs 0.314 ns at tt, mostly wire capacitance; the sign-off margins (uncertainty and derate) cost 0.403 ns; the slow corner is the largest effect.

LibreLane prints 494 Verilator `TIMESCALEMOD` lint warnings. All of them come from LibreLane-generated cell and I/O stub files: none come from our RTL, and there are 0 lint errors.

## Report figures and extra analysis

The required structure has only `report/report.pdf` in `report/`, so the LaTeX source, figures and the helper scripts below are kept next to the repository in `../report_src/` (`report.tex`, `figures/`, `tools/`). Commands run from the repository root inside the container.

Waveform screenshots (report Figure 2): GTKWave is opened headless on `mult.vcd` with the save files `tools/w_11x7.gtkw` and `tools/w_14x7.gtkw` (signals, decimal format, markers at rising edges 1 and 2), the Xvfb framebuffer is converted to PNG, and red latency labels are drawn above the screenshot (`tools/annotate_wave.py`):

```bash
vvp sim                                         # writes mult.vcd
bash ../report_src/tools/waveshots.sh /tmp/waveshots
cp /tmp/waveshots/waveform_11x7.png /tmp/waveshots/waveform_14x7.png ../report_src/figures/
```

The charts in report Figures 3 and 4 (cell area by type, critical-path arrival times, setup slack of the eight runs, and the post-route T_min breakdown) are drawn with pgfplots directly in `report.tex`; their data points are typed in from `synth/mult_array_stat.rpt`, `sta/mult_array_timing.rpt`, each run's `final/metrics.json` and Table 7.

Pre-route to post-route timing decomposition (report Table 7; uses the local `pnr/runs/` folder):

```bash
bash ../report_src/tools/decomp.sh
```

Rebuild the report (host, TeX Live with `float`, `subcaption`, `booktabs`, `enumitem`, `lmodern`):

```bash
cd ../report_src && pdflatex report.tex && pdflatex report.tex && cp report.pdf ../DVD-2023102006-2023112019/report/report.pdf
```

The layout screenshots (report Figure 3) were taken in KLayout from `pnr/mult_array.gds` with the command in Part D. A headless re-render of the submitted GDS with the same layer properties covers 100 % of the full-die screenshot's drawn pixels (99.1 % for run 1's GDS), so the screenshot matches the submitted layout.
