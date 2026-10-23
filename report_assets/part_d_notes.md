# Part D notes — facts only (write the sentences yourself)

All numbers come from pnr/metrics.json (final run, CLOCK_PERIOD 7.0 ns),
synth/mult_array_stat.rpt and sta/mult_array_timing.rpt.

---------------------------------------------------------------------
## A. Tables for the README / report
---------------------------------------------------------------------

### LibreLane attempts (README)
| Attempt | CLOCK_PERIOD (ns) | Run folder              | Setup WS (ns) | DRC | LVS | Result           |
|---------|-------------------|-------------------------|---------------|-----|-----|------------------|
| 1       | 3.5               | RUN_2026-10-22_19-25-27 | -2.144        | 0   | 0   | FAIL (setup, ss) |
| 2       | 4.0               | RUN_2026-10-22_19-27-25 | -1.644        | 0   | 0   | FAIL (setup, ss) |
| 3       | 4.5               | RUN_2026-10-22_19-28-52 | -1.144        | 0   | 0   | FAIL (setup, ss) |
| 4       | 5.0               | RUN_2026-10-22_19-30-19 | -0.644        | 0   | 0   | FAIL (setup, ss) |
| 5       | 5.5               | RUN_2026-10-22_19-31-47 | -0.144        | 0   | 0   | FAIL (setup, ss) |
| 6       | 6.0               | RUN_2026-10-22_19-33-14 | -0.082        | 0   | 0   | FAIL (setup, ss) |
| 7       | 6.5               | RUN_2026-10-22_19-34-43 | -0.165        | 0   | 0   | FAIL (setup, ss) |
| 8       | 7.0               | RUN_2026-10-22_19-36-08 | +0.335        | 0   | 0   | PASS             |

Typical-corner (tt) slack was positive in every run (+0.591 at 3.5 ns ... +3.687 at 7.0 ns).
Every failure was setup at the slow corners (max/nom/min_ss_100C_1v60).

### Part D results table
| Metric                          | Value |
|---------------------------------|-------|
| CLOCK_PERIOD used               | 7.0 ns |
| Number of runs                  | 8 |
| Core area                       | 17759.5 um^2 (die 150 x 150 = 22500 um^2) |
| Cells after synthesis (Part B)  | 73 |
| Cells after place and route     | 1896 (334 std cells + 1562 fill/decap) |
| Kinds of cells added            | tap 245, decap 1313, fill 249, clock buffers 3, buffers 19, diodes 0 |
| Wirelength                      | 2375 um |
| Setup slack                     | +0.335 ns (worst corner, ss); +3.687 ns at tt |
| Post-route F_max                | 1000 / (7.0 - 0.335) = 150.0 MHz |
| F_max from Part C               | 384.6 MHz |
| DRC errors                      | 0 (Magic 0, KLayout 0, routing 0) |
| LVS errors                      | 0 |

### Extra sweep (optional, 1-2 sentences in the report)
Tried 6.1-6.9 ns outside the official procedure:
6.1 -0.179 | 6.2 -0.216 | 6.3 -0.116 | 6.4 -0.016 | 6.6 -0.065 | 6.7 +0.035 PASS | 6.8 +0.135 | 6.9 +0.235 | 7.0 +0.335
- below 6.6 the slack is not monotonic (tool re-optimises for each target)
- from 6.7 up, slack rises exactly with the period -> real ss path delay = 6.665 ns
- so F_max is 150.0 MHz whether you use 6.7 or 7.0; 7.0 kept because it follows the +0.5 ns rule

### Lines recorded from re-running Parts A-C (for your friend)
- RTL sim:        PASS: 256 vectors checked, 0 errors
- Error test:     FAIL: 256 vectors checked, 95 errors   (first: a=3 b=3 expected=9 got=5)
- Gate-level sim: PASS: 256 vectors checked, 0 errors
- STA T=10 ns:    worst slack 7.40 ns
- STA T=2.60 ns:  worst slack 0.00 ns   (T=2.59 -> -0.01)

---------------------------------------------------------------------
## B. Q4 facts — why post-route F_max is lower; why each cell kind was added
---------------------------------------------------------------------
Numbers:
- Part C F_max 384.6 MHz  vs  post-route 150.0 MHz  (about 39 % of Part C)
- post-route at tt corner only: 1000 / (7.0 - 3.687) = 301.8 MHz
  -> tt vs Part C: 384.6 -> 301.8 (wires + clock tree + buffers, ~22 % lower)
  -> ss vs tt:     301.8 -> 150.0 (slow corner alone halves it)

Why lower (points to cover):
- Part C: typical corner (tt, 25 C, 1.80 V), ideal clock, no wire delay
- LibreLane signs off at ALL corners; worst is ss, 100 C, 1.60 V
  (slow transistors + hot + low voltage -> much slower gates)
- real wires: 2375 um routed, their R and C add delay (extracted, SPEF)
- clock tree: 3 clkbuf_16 -> clock arrives with insertion delay/skew, not ideal
- input/output buffers added in front of / after the flops add delay

Cells added (std cells 334 = 16 FF + 48 logic + 3 inv + 245 tap + 3 clkbuf + 19 buf):
- tap (tapvpwrvgnd) x245: tie n-well to VPWR and substrate to VGND -> prevents latch-up
- decap x1313: small capacitors between VPWR and VGND -> keep supply steady when gates switch
- fill x249: fill empty gaps in rows -> continuous wells/rails, meets density rules
- clock buffers (clkbuf_16) x3: clock tree synthesis -> drive all 16 flops, low skew
- buffers x19 (17 buf_2 + 2 clkdlybuf4s50): timing repair / I/O buffering -> drive strength, slew
- diodes x0: antenna repair not needed (short wires) -> say none were added
- note: LibreLane re-synthesised: 67 logic+FF cells vs 73 in Part B (different tool settings,
  e.g. it does not use the lpflow isolation cells that Part B's abc picked)

---------------------------------------------------------------------
## C. Q5 facts — DRC vs LVS
---------------------------------------------------------------------
- DRC = geometry check of the layout against the foundry (SKY130) rules:
  min width, min spacing, enclosure of vias, density...
  Our result: Magic 0, KLayout 0, router 0 errors
- LVS = Layout Versus Schematic: extract the circuit from the layout and compare with the
  netlist (same cells, same connections). Our result: 0 errors (Netgen)
- Why both:
  - DRC clean but LVS fails -> manufacturable chip that is the wrong circuit (short/open/miswire)
  - LVS clean but DRC fails -> right circuit that the fab cannot build reliably (shorts, low yield)
  - masks cost a lot; errors found after fabrication cannot be fixed

---------------------------------------------------------------------
## D. Q6 facts — 8-bit instead of 4-bit
---------------------------------------------------------------------
Counts:
- full adders N(N-1): 4-bit 12 -> 8-bit 56 (4.7x)
- AND gates N^2:      16 -> 64 (4x)
- flip-flops 4N:      16 -> 32 (2x)
- critical path ~2N FA delays: 8 -> 16 (2x)

From the Part C critical path (sta/mult_array_timing.rpt, b_r[0] -> p[6]):
- clk->Q (dfrtp)              0.395 ns
- partial-product AND (and2)  0.212 ns
- adder chain (7 cells)       2.460 - 0.607 = 1.853 ns  -> ~8 FA delays -> t_FA ~ 0.232 ns
- setup time                  0.135 ns
- check: 0.395 + 0.212 + 1.853 + 0.135 = 2.595 ~ Tmin 2.60 ns

8-bit estimate:
- Tmin(8) ~ 0.395 + 0.212 + 16 x 0.232 + 0.135 = 0.742 + 3.71 = ~4.45 ns
- F_max(8) ~ 1000 / 4.45 = ~225 MHz  (vs 384.6 MHz)
- Tmin grows ~1.7x, not exactly 2x, because flop delay + AND + setup (0.742 ns) do not grow
- only an estimate: real synthesis remaps FAs into different cells (see Part C list)

---------------------------------------------------------------------
## E. Block diagram checklist (draw by hand)
---------------------------------------------------------------------
Must show:
[ ] inputs a[3:0], b[3:0] on the left; clk and rst_n going to every register
[ ] input register a_r[3:0] (4 FF) and b_r[3:0] (4 FF)  = 8 FF
[ ] 4x4 grid of 16 AND gates, label pp_i[j] = a_r[j] & b_r[i]
[ ] row 0: AND gates only; pp_0[0] goes straight out as p[0]
[ ] rows 1, 2, 3: 4 full adders each = 12 FA, label them FA(row,j)
[ ] carries ripple left-to-right inside each row (c_i[0] = 0 into the first FA)
[ ] sums drop down to the next row; lowest sum of each row leaves as p[1], p[2], p[3]
[ ] row 3 outputs s_3[3:1] and c_3[4] -> p[7:4]
[ ] output register p[7:0] (8 FF) on the right       -> 16 FF total
[ ] critical path b_r[0] -> p[6] drawn in a different colour (Part C, 2.460 ns arrival)
[ ] caption with a figure number, e.g. "Fig. 1: Block diagram of the 4x4 array multiplier"

Exact wiring (from rtl/mult_array.v) — FA(i,j) = full adder in row i, column j:
  inputs of FA(i,j):  a = pp_i[j],  b = r_(i-1)[j],  cin = c_i[j]  (c_i[0] = 0)
  outputs:            sum s_i[j],  cout c_i[j+1] -> cin of FA(i,j+1)
  r0 = {0, pp0[3], pp0[2], pp0[1]}    -> FA(1,0).b = pp0[1] ... FA(1,3).b = 0
  r1 = {c1[4], s1[3], s1[2], s1[1]}   -> FA(2,0).b = s1[1] ... FA(2,3).b = c1[4]
  r2 = {c2[4], s2[3], s2[2], s2[1]}   -> FA(3,0).b = s2[1] ... FA(3,3).b = c2[4]
  p[0] = pp0[0]   p[1] = s1[0]   p[2] = s2[0]   p[3] = s3[0]
  p[4] = s3[1]    p[5] = s3[2]   p[6] = s3[3]   p[7] = c3[4]
  => each sum s_i[j] (j >= 1) feeds FA(i+1, j-1): one row down, one column towards the LSB; s_i[0] leaves as p[i]

Critical path to highlight (8 FA = 2N, traced from the RTL connections):
  b_r[0] -> AND pp0[1] -> FA(1,0) cout -> FA(1,1) cout -> FA(1,2) cout -> FA(1,3) sum s1[3]
         -> FA(2,2) cout -> FA(2,3) sum s2[3] -> FA(3,2) cout -> FA(3,3) sum s3[3] = p[6] -> p register
  (p[7] has an equally long path; STA picked p[6] after synthesis remapped the gates)

Rough sketch to copy (data flows left -> right, rows top -> bottom):

  a,b -> [a_r|b_r] -> [16 AND] --pp0--> row0 ------------------------------> p[0]
                                --pp1--> row1: FA FA FA FA  (carry ->)   --> p[1]
                                            | sums down
                                --pp2--> row2: FA FA FA FA  (carry ->)   --> p[2]
                                            | sums down
                                --pp3--> row3: FA FA FA FA  (carry ->)   --> p[3], p[7:4]
                                                                   all p -> [p reg] -> p[7:0]

---------------------------------------------------------------------
## F. Paragraph plan for Q4-Q6 (you write the sentences)
---------------------------------------------------------------------
Q4 (about 5-6 sentences):
  1. state both numbers: Part C 384.6 MHz vs post-route 150.0 MHz
  2. Part C assumptions: tt corner, ideal clock, no wire delay
  3. what LibreLane adds: real wires (2375 um RC), clock tree, buffers, ALL corners
  4. the split: tt post-route 301.8 MHz -> slow corner is the main cause
  5. one line per added cell kind (tap, decap, fill, clkbuf, buf, diode=0) and why
Q5 (about 4 sentences):
  1. DRC = geometry vs foundry rules (+ examples)   2. LVS = layout circuit vs netlist
  3. our result: 0 / 0                               4. why both: two different failure examples
Q6 (about 5 sentences + the small calculation):
  1. formulas and counts (56 FA, 64 AND, 16 -> 32 FF)
  2. path 8 -> 16 FA delays
  3. t_FA from Part C (1.853 ns / 8 = 0.232 ns)
  4. Tmin(8) ~ 4.45 ns, F_max ~ 225 MHz
  5. why ~1.7x not 2x (fixed 0.742 ns of flop + AND + setup)

---------------------------------------------------------------------
## G. Part D commands for the README (what was actually run)
---------------------------------------------------------------------
Inside the IIC-OSIC-TOOLS container (image hpretl/iic-osic-tools:latest, LibreLane v3.1.0.dev3),
with the repo at /foss/designs/DVD-2023102006-2023112019:

    cd /foss/designs/DVD-2023102006-2023112019/pnr
    export PDK=sky130A STD_CELL_LIBRARY=sky130_fd_sc_hd
    librelane --manual-pdk --pdk-root $PDK_ROOT -p sky130A -s sky130_fd_sc_hd config.json 2>&1 | tee run1.log
    # timing failed -> raise CLOCK_PERIOD by 0.5 ns in config.json and run again (run2.log ... run8.log)
    # passing run: CLOCK_PERIOD 7.0 ns (attempt 8, RUN_2026-10-22_19-36-08)
    cp runs/RUN_2026-10-22_19-36-08/final/metrics.json .
    cp runs/RUN_2026-10-22_19-36-08/final/gds/mult_array.gds .
    klayout mult_array.gds          # layout screenshots

Note on warnings (one sentence for README/report):
  494 Verilator TIMESCALEMOD lint warnings, all from LibreLane-generated cell/IO stub files
  (0 from our RTL, 0 lint errors); RSZ-0020 "2 floating nets" = VPWR/VGND during resizing,
  connected by the power grid (0 power-grid violations, 0 disconnected pins, 0 LVS errors).
