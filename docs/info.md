## How it works

The checker accepts three additive shares in the range 0–3328, a compressed
ciphertext coefficient, and a compression width. It switches the shares into
a 14-bit modulus, adds them with a rounding correction of two, and checks the
sum against the interval for the received coefficient. The serial divider
handles both share conversion and endpoint correction. The interval can wrap
through zero. Use public test values, since the switched shares are combined
in a register.

## How to test

Run the clock at 10 MHz or slower. Select the design, hold `rst_n` low for at
least one rising edge, then release reset.

| Pins | Function |
| --- | --- |
| `ui[7:0]` | Input byte, with bit 0 the least significant bit |
| `uio[0]` | VALID, active high |
| `uo[0]` | READY, active high |
| `uo[1]` | DONE, result available |
| `uo[2]` | MATCH, accepted if high while DONE is high and ERROR is low |
| `uo[3]` | ERROR, malformed packet |

An input byte is consumed on each rising edge with VALID and READY both
high. Change data and VALID away from the rising edge. Bytes can be queued
back-to-back while READY is high. Leave VALID low when idle.

| Byte index | Data |
| --- | --- |
| 0, 2, 4 | Low eight bits of shares 0, 1, and 2 |
| 1, 3, 5 | High four bits of the corresponding share in bits 3:0, upper bits zero |
| 6 | Low eight bits of the compressed coefficient |
| 7 | Coefficient bits 10:8 in bits 2:0, width selector in bits 4:3, upper bits zero |

Width selectors 0, 1, 2, and 3 select 4, 5, 10, and 11 bits respectively.
After each high share byte, READY stays low for 15 clocks. The result and
READY appear 10 rising edges after the last byte is accepted. DONE, MATCH,
and ERROR hold until the first byte of the next packet or a reset.

Send each row from left to right. Read `uo[3:0]` once DONE is high.

| Bytes in hex | Expected status | Case |
| --- | --- | --- |
| `00 0D 01 00 00 0D 00 00` | `0x7` | Match on the high side of the wrapping 4-bit zero bin |
| `00 0D 01 00 00 0D 01 00` | `0x3` | Same shares with a mismatching coefficient |
| `01 0D 01 00 00 0D 00 00` | `0xB` | Malformed share of 3329 |
| `00 00 00 00 00 00 00 18` | `0x7` | Match for the 11-bit zero bin |

## External hardware

The FPGA board requires a clock, reset, and a digital source for VALID and
the byte bus. A logic analyzer can capture the input handshake and output
status. Use the voltage levels and GPIO assignments of the board in use.
