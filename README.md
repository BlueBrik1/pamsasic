# PAMS Interval Checker

This Tiny Tapeout GF180 prototype checks whether three arithmetic shares encode
an ML-KEM coefficient whose compressed value equals a supplied ciphertext
coefficient. It supports all four compression widths and targets one tile at
10 MHz.

Use public test coefficients because the prototype combines the switched
shares in one register. The [PAMS research repository](https://github.com/bluebrik1/pams)
describes the masked architecture.

## Use

- [Submission checklist](START-HERE.txt)
- [Pinout, packet format, and hardware test vectors](docs/info.md)
- [Run simulation and open the waveform](test/README.md)
- [Local verification results and captures](evidence/VERIFICATION.txt)
- [Tiny Tapeout GF180 Verilog template](https://github.com/TinyTapeout/ttgf-verilog-template/tree/e0d770f2c5683019858465324f6a4c36e94504db)

## Build

Enable Actions and set **Settings → Pages → Source** to **GitHub Actions**
for the Tiny Tapeout layout viewer. The push workflows build the design, run RTL and gate-level
tests, run precheck, and build the datasheet. Run the **fpga** workflow manually
for the Tiny Tapeout iCE40UP5K ASIC simulator bitstream.
