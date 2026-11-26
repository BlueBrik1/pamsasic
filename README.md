# PAMS Interval Checker

This Tiny Tapeout GF180 prototype checks whether three arithmetic shares encode
an ML-KEM coefficient whose compressed value equals a supplied ciphertext
coefficient. It supports all four compression widths and targets one tile at
10 MHz.

Use public test coefficients because the prototype combines the switched
shares in one register. The [PAMS research repository](https://github.com/bluebrik1/pams)
describes the masked architecture.
