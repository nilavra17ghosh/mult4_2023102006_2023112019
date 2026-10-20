# Execution Plan: 4-bit Array Multiplier, RTL to GDSII (SKY130)

This is a step-by-step guide for doing the whole assignment on Ubuntu. Read it once from start to finish, then work through it phase by phase.

> **Status:** `rtl/`, `tb/`, `synth/synth.tcl`, `sta/sta.tcl`, `pnr/config.json`, `README.md` and `.gitignore` are already written in the repo. Where the code below differs, **the repo files are authoritative**. What remains on Ubuntu: running everything, filling in the `TODO`s, setting `CLOCK_PERIOD` after Part C, screenshots and the report.
>
> **Delete this file (`git rm PLAN.md`) before you submit.** The assignment asks for *exactly* the file architecture in Section 5.

---

## 0. Summary

| Phase | What you do | Output | Marks |
|---|---|---|---|
| 0 | Install Docker and IIC-OSIC-TOOLS, clone the repo | Working tools | – |
| A | Write the full adder, the multiplier and the testbench; simulate | `rtl/*.v`, `tb/tb_mult.v`, PASS/FAIL lines, waveform | 30 |
| B | Synthesise with Yosys; run gate-level simulation (GLS) | `synth/*` and the Part B table | 20 |
| C | Run STA with OpenSTA; find Tmin and Fmax | `sta/*` and the Part C table | 20 |
| D | Run LibreLane to GDS; view it in KLayout | `pnr/*`, the Part D table, 2 screenshots | 30 |
| R | Write the README and the report | `README.md`, `report/report.pdf` | – |

Values that are fixed throughout:
- Roll number used for the example: **2023102006**, last digit 6, so **A = 6 + 5 = 11** and **B = 7**. (If your partner's roll number is used instead, recompute A and say whose number it is.)
- All commands run **from the repo root inside the container**, unless a step says otherwise.
- **Make at least 5 commits spread over the two weeks.** Commit points are marked 🔖.

---

## Phase 0: Environment on Ubuntu

### 0.1 Install Docker and git (host Ubuntu terminal)
```bash
sudo apt update
sudo apt install -y docker.io git
sudo usermod -aG docker $USER
newgrp docker            # or log out and back in
docker run hello-world   # must print "Hello from Docker!"
```
You need at least 20 GB of free disk space and at least 8 GB of RAM.

### 0.2 Put the repo where the container can see it
```bash
mkdir -p ~/eda/designs
cd ~/eda/designs
git clone <YOUR-REPO-URL> DVD-2023102006
```
`~/eda/designs` on the host appears as **`/foss/designs`** inside the container. Work only in this folder, or your work is lost when the container stops.

### 0.3 Get and start IIC-OSIC-TOOLS
```bash
cd ~
git clone --depth 1 https://github.com/iic-jku/IIC-OSIC-TOOLS.git
cd IIC-OSIC-TOOLS
docker pull hpretl/iic-osic-tools:latest     # large download, do this first
./start_x.sh       # Linux: GUI apps (gtkwave, klayout) open as normal windows
# or: ./start_vnc.sh  then open http://localhost in a browser (default VNC password: abc123)
```
If `start_x.sh` gives a display error, run `xhost +local:` on the host and try again. Check the README "Quick launch" section if any script name has changed.

### 0.4 Check the tools (terminal inside the container)
```bash
iverilog -V | head -1
yosys -V
sta -version
librelane --version
echo $PDK_ROOT $PDK          # must show .../pdks sky130A
# if PDK is not sky130A:
sak-pdk sky130A
ls $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
ls $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/{primitives.v,sky130_fd_sc_hd.v}
```
Save these version lines; they are useful in the README.

### 0.5 Create the folder skeleton
```bash
cd /foss/designs/DVD-2023102006
mkdir -p rtl tb synth sta pnr report
```
Optional `.gitignore`. It keeps large and generated files out of git:
```
sim
gls
*.vcd
pnr/runs/
```
Use git (commit/push) from the **host** terminal in `~/eda/designs/DVD-2023102006`. It is the same folder.

---

## Phase A: RTL Design and Verification (30 marks)

### A.1 `rtl/full_adder.v`
The full adder must be written with `assign` statements.
```verilog
`timescale 1ns/1ps
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    assign sum  = a ^ b ^ cin;
    assign cout = (a & b) | (b & cin) | (a & cin);
endmodule
```

### A.2 `rtl/mult_array.v`
Rules: exactly 12 `full_adder` instances, **no `*` operator**, async active-low reset, 16 flip-flops (4 for `a`, 4 for `b`, 8 for `p`). The connections follow the table in Section 2 exactly.
```verilog
`timescale 1ns/1ps
module mult_array (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg  [7:0] p
);
    // ---------------- input registers ----------------
    reg [3:0] a_r, b_r;

    // ---------------- partial products: pp_i[j] = a[j] & b[i] (16 AND gates) ----------------
    wire [3:0] pp0 = a_r & {4{b_r[0]}};
    wire [3:0] pp1 = a_r & {4{b_r[1]}};
    wire [3:0] pp2 = a_r & {4{b_r[2]}};
    wire [3:0] pp3 = a_r & {4{b_r[3]}};

    // ---------------- row 0: no adders ----------------
    wire [3:0] r0 = {1'b0, pp0[3], pp0[2], pp0[1]};

    // ---------------- rows 1..3: 4-bit ripple-carry adders ----------------
    wire [3:0] s1, s2, s3;
    wire [4:0] c1, c2, c3;
    assign c1[0] = 1'b0;
    assign c2[0] = 1'b0;
    assign c3[0] = 1'b0;

    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : row1
            full_adder fa (.a(pp1[j]), .b(r0[j]), .cin(c1[j]), .sum(s1[j]), .cout(c1[j+1]));
        end
    endgenerate
    wire [3:0] r1 = {c1[4], s1[3], s1[2], s1[1]};

    generate
        for (j = 0; j < 4; j = j + 1) begin : row2
            full_adder fa (.a(pp2[j]), .b(r1[j]), .cin(c2[j]), .sum(s2[j]), .cout(c2[j+1]));
        end
    endgenerate
    wire [3:0] r2 = {c2[4], s2[3], s2[2], s2[1]};

    generate
        for (j = 0; j < 4; j = j + 1) begin : row3
            full_adder fa (.a(pp3[j]), .b(r2[j]), .cin(c3[j]), .sum(s3[j]), .cout(c3[j+1]));
        end
    endgenerate

    // ---------------- product bits ----------------
    wire [7:0] p_next = {c3[4], s3[3], s3[2], s3[1], s3[0], s2[0], s1[0], pp0[0]};

    // ---------------- registers (async active-low reset) ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r <= 4'd0;
            b_r <= 4'd0;
            p   <= 8'd0;
        end else begin
            a_r <= a;
            b_r <= b;
            p   <= p_next;
        end
    end
endmodule
```
Make sure you can explain every line. The viva or the academic-integrity check may ask you to.

### A.3 `tb/tb_mult.v`
Requirements: 10 ns clock; `rst_n` low for the first 2 cycles; all 256 vectors; wait 2 cycles of latency for each; print every mismatch; print exactly one summary line; write `mult.vcd`.

Timing scheme: inputs change on the **falling** edge. Edge 1 (rising) captures `a_r`/`b_r`. Edge 2 (rising) captures `p`. The check happens on the next falling edge. This scheme is race-free and also works for the gate-level simulation with `#1` unit delays.
```verilog
`timescale 1ns/1ps
module tb_mult;
    reg        clk;
    reg        rst_n;
    reg  [3:0] a, b;
    wire [7:0] p;

    integer i, j;
    integer errors;
    integer count;

    mult_array dut (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .p(p));

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("mult.vcd");
        $dumpvars(0, tb_mult);

        rst_n  = 1'b0;
        a      = 4'd0;
        b      = 4'd0;
        errors = 0;
        count  = 0;

        // hold reset low for the first 2 clock cycles
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i;                // applied on a falling edge
                b = j;
                @(posedge clk);       // edge 1: inputs registered
                @(posedge clk);       // edge 2: product registered
                @(negedge clk);       // let outputs settle, then check
                count = count + 1;
                if (p !== i * j) begin
                    errors = errors + 1;
                    $display("MISMATCH: a=%0d b=%0d expected=%0d got=%0d (t=%0t)",
                             i, j, i * j, p, $time);
                end
            end
        end

        if (errors == 0)
            $display("PASS: %0d vectors checked, %0d errors", count, errors);
        else
            $display("FAIL: %0d vectors checked, %0d errors", count, errors);
        $finish;
    end
endmodule
```

### A.4 Simulate (container, from the repo root)
```bash
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim                      # expect: PASS: 256 vectors checked, 0 errors
gtkwave mult.vcd &
```
Copy the PASS line exactly into your notes.

🔖 **Commit 1:** `git add rtl tb && git commit -m "Add full adder, array multiplier RTL and exhaustive testbench"`

### A.5 Find the example in the waveform: 11 × 7
In this testbench, vector *k* = 16·a + b is applied at t = 20 + 20k ns. For a = 11, b = 7, k = 183:
- inputs change at **3680 ns**
- edge 1 at **3685 ns** (a_r = 11, b_r = 7)
- edge 2 at **3695 ns**: **p becomes 77** (0x4D) and stays 77 until 3715 ns

In GTKWave:
1. Add `clk`, `rst_n`, `a`, `b`, `p`. Use the SST panel and the `tb_mult` scope.
2. Right-click `a`, `b`, `p` and choose **Data Format → Decimal**.
3. Zoom to about 3670–3720 ns.
4. Place markers at 3685 ns and 3695 ns (middle-click or the marker tools) to show the 2-cycle latency.
5. Take a screenshot (`gnome-screenshot -a` on the host, or the PrintScreen key). Also take one screenshot of the reset area (0–30 ns), which shows `rst_n` low for 2 cycles.

### A.6 Hand-worked example (put this in the report)
```
            1 0 1 1      A = 11
          x 0 1 1 1      B = 7
        ---------------
            1 0 1 1      pp0 = A AND b0 (b0 = 1)
          1 0 1 1        pp1 = A AND b1 (b1 = 1), shifted 1
        1 0 1 1          pp2 = A AND b2 (b2 = 1), shifted 2
      0 0 0 0            pp3 = A AND b3 (b3 = 0), shifted 3
      ---------------
      0 1 0 0 1 1 0 1    P = 77
```
Trace through the array. This trace is worth including because it shows you understand the structure.

| Row | Adds | Result | Product bit out | Passed down |
|---|---|---|---|---|
| 0 | – | pp0 = 1011 | p[0] = 1 | r0 = 0101 |
| 1 | pp1 1011 + r0 0101 | 1 0000 (16) | p[1] = 0 | r1 = 1000 |
| 2 | pp2 1011 + r1 1000 | 1 0011 (19) | p[2] = 1 | r2 = 1001 |
| 3 | pp3 0000 + r2 1001 | 0 1001 (9) | p[3] = 1 | p[7:4] = 0100 |

Result: p = 0100_1101 = **77** ✓

### A.7 Error-injection test
```bash
sed -i 's/assign sum  = a ^ b ^ cin;/assign sum  = a ^ b;/' rtl/full_adder.v
grep "assign sum" rtl/full_adder.v                 # confirm the change
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim | tail -5                                  # expect: FAIL: 256 vectors checked, N errors
git checkout rtl/full_adder.v                      # UNDO (or edit it back by hand)
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v && vvp sim | tail -1   # PASS again
```
Record the exact FAIL line, including the error count, and a few MISMATCH lines.

### A.8 Block diagram
Draw it by hand or in draw.io. It must show:
- input registers `a_r[3:0]` and `b_r[3:0]` (8 DFFs) with clk and rst_n
- the 4×4 grid of **16 AND gates** (pp_i[j])
- **3 rows of 4 full adders = 12 FAs**, with carry rippling left within each row and sums dropping to the next row; mark where p[0]…p[3] leave, and p[7:4] from row 3
- the output register `p[7:0]` (8 DFFs)
- Label the longest path (described in Phase C).

---

## Phase B: Logic Synthesis with Yosys (20 marks)

### B.1 `synth/synth.tcl`
```tcl
# Yosys synthesis script for mult_array (SKY130 sky130_fd_sc_hd, tt corner)
# Run from the repo root:  yosys -c synth/synth.tcl
set lib $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# 1. Read the design
yosys read_verilog rtl/full_adder.v rtl/mult_array.v
# 2. Generic synthesis, flatten the full adders into one module
yosys synth -top mult_array -flatten
# 3. Map flip-flops to SKY130 flip-flop cells
yosys dfflibmap -liberty $lib
# 4. Map the logic to SKY130 gate cells
yosys abc -liberty $lib
# 5. Remove unused wires
yosys opt_clean -purge
# 6. Cell and area report
yosys tee -o synth/mult_array_stat.rpt stat -liberty $lib
# 7. Gate-level netlist
yosys write_verilog -noattr synth/mult_array_netlist.v
```
Run it:
```bash
yosys -c synth/synth.tcl | tee synth/yosys.log    # yosys.log is only for you; don't commit it
cat synth/mult_array_stat.rpt
grep -c dfrtp synth/mult_array_netlist.v           # should be 16
```

### B.2 Fill in the Part B table from `mult_array_stat.rpt`
| Metric | Where to find it |
|---|---|
| Total number of cells | `Number of cells:` line |
| Number of flip-flops | count of `sky130_fd_sc_hd__dfrtp_*` (must be **16**) |
| Total cell area (µm²) | `Chip area for module '\mult_array':` |
| Flip-flop area (µm²) | 16 × area of one `dfrtp_1`. Newer Yosys prints the area per cell type in the report. Otherwise `grep -A3 "cell (\"sky130_fd_sc_hd__dfrtp_1\")" $lib \| grep area` (about 25.02 µm²) |
| FF area % | FF area ÷ total area × 100 |
| Top 3 cell types | the three largest counts in the cell list |
| Netlist sim result | from B.3 |

If you don't see exactly 16 flip-flops, something in the RTL is wrong (for example, a missing reset, or a register optimised away).

### B.3 Gate-level simulation
```bash
CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls \
  tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v
vvp gls          # expect: PASS: 256 vectors checked, 0 errors
```
Note: this overwrites `mult.vcd` with the gate-level waveform. Rerun `vvp sim` afterwards if you still need the RTL waveform. Timescale warnings from iverilog are harmless.

🔖 **Commit 2:** `git add synth/synth.tcl synth/mult_array_netlist.v synth/mult_array_stat.rpt && git commit -m "Add Yosys synthesis script, netlist and area report"`

---

## Phase C: Static Timing Analysis with OpenSTA (20 marks)

### C.1 `sta/sta.tcl`
The period defaults to 10 ns. You can override it with an environment variable, so you don't need to edit the file for every run.
```tcl
# OpenSTA script for mult_array (typical corner tt_025C_1v80)
# Run from the repo root:  sta sta/sta.tcl        (T = 10 ns)
#                    or:   T=2.73 sta sta/sta.tcl  (any other period)
set lib $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set T 10.0
if {[info exists ::env(T)]} { set T $::env(T) }

# 1. Read the cell timing library
read_liberty $lib
# 2. Read and link the netlist
read_verilog synth/mult_array_netlist.v
link_design mult_array
# 3. Clock with period T ns
create_clock -name clk -period $T [get_ports clk]
# 4. Input arrival time
set_input_delay 1.0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
# 5. Output required time
set_output_delay 1.0 -clock clk [all_outputs]
# 6. Worst setup slack
puts "Clock period T = $T ns"
report_worst_slack -max
# 7. Critical path report
report_checks -path_delay max -digits 3 > sta/mult_array_timing.rpt
exit
```

### C.2 Find Tmin and Fmax
```bash
sta sta/sta.tcl                  # note "worst slack X" = WNS at T = 10
cat sta/mult_array_timing.rpt
```
- **Tmin = 10 − WNS**, rounded to 0.01 ns. For example, WNS = 7.27 gives Tmin = 2.73.
- **Fmax = 1000 / Tmin** MHz.
- Confirm: `T=<Tmin> sta sta/sta.tcl` should report a slack close to 0 (|slack| < 0.01).
- **For submission, regenerate the report at the T you want to show.** The table asks for the critical path, which is the same at any T. A sensible final state is the report at T = 10 ns, plus a note in the README of the Tmin run. Record both runs in the README.

### C.3 Read the critical path
```bash
grep -E "Startpoint|Endpoint|slack" sta/mult_array_timing.rpt
grep -oE "\(sky130_fd_sc_hd__[a-z0-9_]+\)" sta/mult_array_timing.rpt     # cells in order
```
- The start point should be an **input register** flip-flop (an `a_r`/`b_r` bit, `dfrtp`, clocked by clk). The end point should be an **output register** flip-flop (most likely `p[7]` or `p[6]`). In-to-reg and reg-to-out paths are short (1 ns budget each side), so they are not critical.
- List each cell in order: the launch flop (clk→Q), then the AND/NAND gate that forms a partial product, then the XOR/XNOR/MAJ/AOI/OAI cells from the adder rows, and finally the D pin of the capture flop.
- **Count the full-adder cells:** every cell after the partial-product gate is part of the FA chain. Compare this count with the estimate 2N = 8 FA delays. ABC flattens and remaps the logic, so one FA may become 1–3 cells (e.g. `xor3`/`maj3`, or `xnor2`+`a21oi`). Some FAs on the path are simplified to half adders because cin = 0 or one input is the constant 0 (`r0[3]`). This explains why the count is not exactly 8.

### C.4 Part C table
| Metric | Value |
|---|---|
| Worst slack at T = 10 ns | from the run |
| Tmin | 10 − WNS |
| Fmax (MHz) | 1000 / Tmin |
| Slack at T = Tmin | ≈ 0 |
| Critical path start / end point | from the report |
| Number of cells on the critical path | from the grep (state whether you include the launch flop) |
| Latency (ns) | 2 × Tmin |
| Throughput (M results/s) | = Fmax in MHz |

🔖 **Commit 3:** `git add sta && git commit -m "Add OpenSTA script and critical path report"`

---

## Phase D: Physical Design with LibreLane (30 marks)

### D.1 Choose CLOCK_PERIOD
CLOCK_PERIOD = 1.2 × Tmin, **rounded up to the next 0.5 ns**. Example: Tmin = 2.73 gives 3.276, which rounds up to **3.5**.

### D.2 `pnr/config.json`
```json
{
    "DESIGN_NAME": "mult_array",
    "VERILOG_FILES": ["dir::../rtl/full_adder.v", "dir::../rtl/mult_array.v"],
    "CLOCK_PORT": "clk",
    "CLOCK_PERIOD": 3.5,
    "FP_SIZING": "absolute",
    "DIE_AREA": [0, 0, 150, 150]
}
```
Replace `3.5` with your value. `dir::` means "relative to the folder this config is in", so `../rtl` points to the repo's `rtl/` folder.

### D.3 Run the flow
```bash
cd /foss/designs/DVD-2023102006/pnr
librelane config.json 2>&1 | tee run1.log
# if it complains about the PDK version / ciel / volare:
librelane --manual-pdk config.json 2>&1 | tee run1.log
# alternative: python3 -m librelane config.json
```
A run takes 5–15 minutes and creates `pnr/runs/RUN_<date-time>/`. The final outputs are in `runs/RUN_*/final/`.

**Pass criteria:** 0 DRC errors, 0 LVS errors, setup slack ≥ 0. If setup fails, **increase CLOCK_PERIOD by 0.5 ns and rerun**. Record *every* attempt (period, result, run folder) in the README.

### D.4 Copy the deliverables
```bash
cd /foss/designs/DVD-2023102006/pnr
RUN=$(ls -td runs/*/ | head -1)       # newest run
ls $RUN/final                         # see the folder layout
cp $RUN/final/metrics.json .
cp $RUN/final/gds/mult_array.gds .    # path may differ by version: find $RUN/final -name "*.gds"
```
**Never commit `pnr/runs/`.** It is huge.

### D.5 Extract the numbers from `metrics.json`
```bash
grep -E "instance__count\"|core__area|die__area|wirelength|setup__ws|drc|lvs" metrics.json
grep -E "instance__count__class" metrics.json        # per-class counts (fill, tap, buffers...)
```
- **Setup slack:** use `timing__setup__ws` (the worst over all corners). Also record `timing__setup__ws__corner:nom_tt_025C_1v80`, because Part C used the tt corner. State in the report which value you used. LibreLane checks several corners (tt/ss/ff); the ss corner is the slowest.
- **DRC:** `magic__drc_error__count`, `klayout__drc_error__count`, `route__drc_errors` must all be 0.
- **LVS:** `design__lvs_error__count` must be 0.
- **Post-route Fmax** = 1000 / (CLOCK_PERIOD − setup slack). Compare it with Part C's Fmax.

### D.6 Which cells were added
```bash
DEF=$(find $RUN/final -name "*.def" | head -1)
grep -oE "sky130_fd_sc_hd__[a-z0-9_]+" $DEF | sed -E 's/_[0-9]+$//' | sort | uniq -c | sort -rn
grep -oE "sky130_fd_sc_hd__[a-z0-9_]+" $DEF | grep -E "buf|fill|tap|decap|clkbuf|diode" | sort | uniq -c
```
Expect these kinds of cells: **tapvpwrvgnd** (well taps), **decap** (decoupling capacitors), **fill** (filler cells), **clkbuf** (CTS buffers), **buf** (input/output and timing-repair buffers), and possibly **diode** (antenna repair). Compare the instance count with the cell count from Part B. Note that LibreLane runs its own synthesis, so its logic-cell count can differ a little from yours.

### D.7 Layout screenshots (KLayout)
```bash
# option 1: LibreLane opens the last run with the right SKY130 layer colours
cd /foss/designs/DVD-2023102006/pnr
librelane --last-run --flow OpenInKLayout config.json
# option 2: plain klayout with the PDK layer properties
klayout -nn $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyt \
        -l  $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp mult_array.gds
# option 3 (fallback): klayout mult_array.gds
```
Screenshot 1: the whole die (press `F2` or "Zoom fit"; set the hierarchy depth to show everything: Display → Full Hierarchy, or `*`). Screenshot 2: zoom in until the standard-cell rows (alternating VPWR/VGND rails) and the metal wires (li1, met1, met2…) are clearly visible.

🔖 **Commit 4:** `git add pnr/config.json pnr/metrics.json pnr/mult_array.gds && git commit -m "Add LibreLane config and final GDS/metrics"`

### D.8 Part D table
CLOCK_PERIOD used · number of runs · core area (`design__core__area`) · cells after synthesis (Part B) · cells after P&R (`design__instance__count`) · kinds of cells added · wirelength (`route__wirelength`) · setup slack · post-route Fmax · Part C Fmax · DRC errors · LVS errors.

---

## Phase R: README and Report

### R.1 `README.md` template
```markdown
# 4-bit Array Multiplier: RTL to GDSII (SKY130)

| Name | Roll number |
|---|---|
| Nilavra Ghosh | 2023102006 |
| <Partner name> | <roll number> |

Example used in Part A: A = 6 + 5 = 11 (last digit of 2023102006, Nilavra Ghosh), B = 7.

Environment: IIC-OSIC-TOOLS Docker image <tag>, iverilog <ver>, yosys <ver>, OpenSTA <ver>, LibreLane <ver>.
All commands are run from the repo root (/foss/designs/DVD-2023102006) unless stated otherwise.

## Part A: RTL simulation
    iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
    vvp sim
    gtkwave mult.vcd
Result: PASS: 256 vectors checked, 0 errors
Error test (sum = a ^ b): <exact sed/edit command>, then the same 2 commands -> FAIL: 256 vectors checked, N errors; reverted with <command>.

## Part B: Synthesis
    yosys -c synth/synth.tcl
    CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
    iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v
    vvp gls

## Part C: STA
    sta sta/sta.tcl              # T = 10 ns -> WNS = ...
    T=<Tmin> sta sta/sta.tcl     # slack = ...

## Part D: Place and route
    cd pnr
    librelane config.json
    cp runs/<RUN>/final/metrics.json .
    cp runs/<RUN>/final/gds/mult_array.gds .
    klayout mult_array.gds

| Attempt | CLOCK_PERIOD (ns) | Run folder | Setup WS (ns) | DRC | LVS | Result |
|---|---|---|---|---|---|---|
| 1 | ... | RUN_... | ... | 0 | 0 | pass/fail |
```

### R.2 `report/report.pdf` contents (in this order)
1. Title, team members, roll numbers
2. **Part A:** block diagram; hand-worked 11 × 7 with the row trace; PASS line; FAIL line from the error test; waveform screenshot with the 2-cycle latency marked
3. **Part B:** completed table; GLS PASS line
4. **Part C:** completed table; ordered list of critical-path cells; FA cell count compared with 2N
5. **Part D:** completed table; the 2 KLayout screenshots
6. **Answers to Q1–Q6** (one paragraph each, using *your* numbers):
   - **Q1:** logic cells = total − 16. They differ from 16 + 28 because the tools flatten and remap logic: one FA becomes several gates (XOR, XNOR, MAJ, AOI/OAI…), and AND gates are merged into larger complex gates (e.g. `a21oi`, `nand2` + inversion absorbed). The FAs with cin = 0 or a constant 0 input (`r0[3] = 0`) reduce to half adders or wires. ABC optimises for area/delay, not for a 1:1 mapping.
   - **Q2:** the path from an input-register flop (`a_r`/`b_r`) through a partial-product AND gate, the row 1 → row 2 → row 3 ripple chain, to the `p[7]`/`p[6]` flop. Give the cell count and compare it with 2N = 8 (see C.3).
   - **Q3:** FF % from Part B. It is large because 16 `dfrtp` cells (≈25 µm² each, one of the biggest cells in the library) are needed regardless of size. The combinational logic is tiny (~N²), while the registers scale with I/O width (4N).
   - **Q4:** post-route timing includes real wire RC (extracted parasitics), clock skew and insertion delay after CTS, I/O buffers, real slews and loads, and multi-corner (ss) analysis. Part C used ideal zero-wire-load and an ideal clock. Added cells: **taps** (tie N-well/substrate to VPWR/VGND to prevent latch-up), **decaps** (stabilise the supply against IR drop and noise), **fill** (continuity of wells and rails, density rules), **clkbuf** (balanced clock tree, low skew), **buf** (drive strength for I/O and long wires, timing/slew repair), **diodes** (antenna protection). If your post-route Fmax is *not* lower, say so honestly and explain why (e.g. LibreLane resized cells and repaired timing).
   - **Q5:** DRC checks the layout against the foundry's geometric rules (minimum width, spacing, enclosure, density), so that the layout can be manufactured with good yield. LVS checks that the transistor/cell netlist extracted from the layout matches the schematic/netlist, i.e. that the layout implements the intended circuit (no shorts, opens or mis-wiring). Both must pass: a layout can be manufacturable but logically wrong (LVS fails), or logically right but unmanufacturable (DRC fails).
   - **Q6:** N = 8 needs N(N − 1) = **56 FAs** compared with 12 (4.7×) and N² = **64 AND gates** compared with 16. The critical path is about 2N = **16 FA delays** compared with 8, so roughly **2×**. Estimate t_FA ≈ (Tmin − t_clk→Q − t_setup − t_AND) / 8 from your report. Then Tmin(8) ≈ t_clk→Q + t_setup + t_AND + 16·t_FA. Show the numbers.
7. Export to PDF and save it as `report/report.pdf`.

🔖 **Commit 5:** `git add README.md report/report.pdf && git commit -m "Add README with all commands and final report"`

Also remove the planning file:
```bash
git rm PLAN.md && git commit -m "Remove planning notes" && git push
```

---

## Suggested 2-week schedule (keeps the git history spread out)

| Day | Work | Commit |
|---|---|---|
| 1–2 | Phase 0 setup; start the image download early | – |
| 3–4 | Phase A: RTL, testbench, PASS, error test, waveform, hand example | 🔖 1 |
| 5–6 | Phase B: synthesis, GLS, table | 🔖 2 |
| 7–8 | Phase C: STA, Tmin/Fmax, critical path | 🔖 3 |
| 9–11 | Phase D: LibreLane runs, screenshots, table | 🔖 4 (+ one per extra run attempt in the README) |
| 12–13 | Block diagram, README, report, Q1–Q6 | 🔖 5 |
| 14 | Final check against the checklist below, remove PLAN.md, push | 🔖 6 |

Split the work: one person can do A and B while the other sets up Docker and prepares C and D. Each person should commit their own parts.

---

## Final checklist

- [ ] Files exactly as in Section 5: `README.md`, `rtl/full_adder.v`, `rtl/mult_array.v`, `tb/tb_mult.v`, `synth/{synth.tcl,mult_array_netlist.v,mult_array_stat.rpt}`, `sta/{sta.tcl,mult_array_timing.rpt}`, `pnr/{config.json,metrics.json,mult_array.gds}`, `report/report.pdf`
- [ ] No `pnr/runs/`, `sim`, `gls`, `*.vcd`, or `PLAN.md` committed
- [ ] `mult_array` has exactly 12 `full_adder` instances, no `*`, ports `clk rst_n a b p`, 16 FFs
- [ ] `full_adder` uses `assign` only; ports `a b cin sum cout`
- [ ] RTL PASS line, FAIL line (error test), GLS PASS line all recorded
- [ ] Waveform screenshot with the latency marked; hand example; block diagram
- [ ] Part B, C and D tables complete; critical-path cell list
- [ ] LibreLane: 0 DRC, 0 LVS, slack ≥ 0; every attempt in the README
- [ ] 2 KLayout screenshots
- [ ] Q1–Q6 answered with your own numbers
- [ ] ≥ 5 meaningful commits spread over the 2 weeks

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER`, then log out and back in |
| GUI doesn't open with `start_x.sh` | `xhost +local:` on the host, or use `./start_vnc.sh` and a browser |
| `.lib not found` | `echo $PDK_ROOT $PDK`; run `sak-pdk sky130A` |
| `Unknown module full_adder` | include `rtl/full_adder.v` in the command |
| RTL FAIL | check every FA's connections against the Section 2 table; look at the first MISMATCH in GTKWave |
| GLS fails but RTL passes | all registers reset? correct model files? exact command from B.3 |
| `sta` stays at a `%` prompt | the script is missing `exit`; type `exit` |
| LibreLane PDK/ciel/volare version error | `librelane --manual-pdk config.json` |
| LibreLane fails at PDN (power grid) on the small die | check `FP_SIZING` / `DIE_AREA`. If it still fails, add smaller PDN pitches, e.g. `"PDN_VPITCH": 25, "PDN_HPITCH": 25` (older versions: `FP_PDN_VPITCH`/`FP_PDN_HPITCH`), and record this in the README |
| Setup violations | CLOCK_PERIOD += 0.5 and rerun |
| Very slow or crashes | give Docker more RAM/CPUs; close other apps |
