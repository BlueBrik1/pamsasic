# Simulate the interval checker

Use GNU Make, Icarus Verilog, Python and GTKWave. In this directory, create
and activate a virtual environment, then install the pinned test packages
and run the suite.

```sh
python -m pip install -r requirements.txt
make -B
python -m cocotb_tools.check_results results.xml
```

The RTL suite checks reset and deselection, valid/ready timing,
malformed packets, and both sides of every compression interval. Its
reference model reconstructs the coefficient and applies integer
compression independently of the RTL.

Generate the short match, mismatch and error capture for GTKWave.

```sh
make -B COCOTB_TEST_FILTER=waveform_example
python -m cocotb_tools.check_results results.xml
gtkwave tb.fst tb.gtkw
```

Use `make -B FST= COCOTB_TEST_FILTER=waveform_example` to write `tb.vcd`
instead. For gate-level simulation, copy the hardened Verilog netlist to
`gate_level_netlist.v`, set `PDK_ROOT` to the directory containing
`gf180mcuD`, and run `make -B GATES=yes`. The gate-level suite samples
boundary cases from every mode and repeats the interface and error tests.
