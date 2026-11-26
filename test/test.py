import os
import random

import cocotb
from cocotb.triggers import Timer

Q = 3329
WIDTHS = (4, 5, 10, 11)
READY, DONE, MATCH, ERROR = (1, 2, 4, 8)


def compress(coefficient, width):
    return (((coefficient << width) + Q // 2) // Q) & ((1 << width) - 1)


def encode(shares, code, mode):
    packet = bytearray()
    for share in shares:
        packet.extend(share.to_bytes(2, "little"))
    packet.extend((code & 255, (code >> 8) | (mode << 3)))
    return packet


class Interface:
    def __init__(self, dut):
        self.dut = dut
        self.status = 0

    async def tick(self, data=0, valid=False):
        self.dut.clk.value = 0
        self.dut.ui_in.value = data
        self.dut.uio_in.value = int(valid)
        await Timer(50, unit="ns")
        self.dut.clk.value = 1
        await Timer(50, unit="ns")
        self.status = int(self.dut.uo_out.value)
        return self.status

    async def reset(self):
        self.dut.ena.value = 1
        self.dut.rst_n.value = 0
        assert await self.tick() == 0
        self.dut.rst_n.value = 1
        assert await self.tick() == READY
        assert int(self.dut.uio_oe.value) == 0
        assert int(self.dut.uio_out.value) == 0

    async def send(self, packet, poison_busy=False):
        for index, value in enumerate(packet):
            assert self.status & READY
            status = await self.tick(value, valid=True)
            if index in (1, 3, 5, 7):
                delay = 10 if index == 7 else 15
                for _ in range(delay):
                    assert status == 0, f"released backpressure early at byte {index}"
                    # VALID during backpressure must never consume this byte.
                    status = await self.tick(0xFF, valid=poison_busy)
                assert status & READY, f"still busy at byte {index}"
            if index != 7:
                assert status == READY
        return self.status

    async def check(self, shares, code, mode):
        expected = compress(sum(shares) % Q, WIDTHS[mode]) == code
        status = await self.send(encode(shares, code, mode))
        assert status == READY | DONE | (MATCH if expected else 0), (
            f"shares={shares} c={code} d={WIDTHS[mode]} status={status}"
        )


@cocotb.test()
async def waveform_example(dut):
    bus = Interface(dut)
    await bus.reset()
    shares = (3328, 1, 3328)
    valid = encode(shares, 0, 0)
    mismatch = encode(shares, 1, 0)
    malformed = encode((3329, 1, 3328), 0, 0)
    for packet, expected in (
        (valid, READY | DONE | MATCH),
        (mismatch, READY | DONE),
        (malformed, READY | DONE | ERROR),
    ):
        assert await bus.send(packet) == expected
        for _ in range(4):
            assert await bus.tick() == expected


@cocotb.test()
async def handshake_and_invalid_frames(dut):
    bus = Interface(dut)
    await bus.reset()

    valid = encode((7, 0, 0), 0, 0)
    # An idle cycle between bytes is ignored.
    assert await bus.tick(valid[0], valid=True) == READY
    assert await bus.tick(0xFF) == READY
    assert await bus.tick(valid[1], valid=True) == 0
    await bus.reset()
    assert await bus.send(valid, poison_busy=True) == READY | DONE | MATCH
    assert await bus.tick() == READY | DONE | MATCH

    # Deselect mid-frame and then restart from byte zero.
    assert await bus.tick(valid[0], valid=True) == READY
    dut.ena.value = 0
    assert await bus.tick(valid[1], valid=True) == 0
    dut.ena.value = 1
    assert await bus.tick() == READY

    for position, bad_byte in ((1, 0x10), (3, 0x0F), (5, 0x80), (7, 0x20)):
        packet = valid.copy()
        packet[position] = bad_byte
        assert await bus.send(packet) == READY | DONE | ERROR
    for mode, width in enumerate(WIDTHS[:-1]):
        assert await bus.send(encode((0, 0, 0), 1 << width, mode)) == READY | DONE | ERROR
    assert await bus.send(valid) == READY | DONE | MATCH


@cocotb.test()
async def compression_boundaries(dut):
    bus = Interface(dut)
    await bus.reset()
    rng = random.Random(3329)
    gate_level = os.getenv("PAMS_GATE_LEVEL") == "1"
    cases = 0
    for mode, width in enumerate(WIDTHS):
        first = {}
        last = {}
        prior_code = compress(Q - 1, width)
        for coefficient in range(Q):
            code = compress(coefficient, width)
            if code != prior_code:
                first[code] = coefficient
                last[prior_code] = (coefficient - 1) % Q
            prior_code = code
        assert len(first) == len(last) == 1 << width

        codes = sorted(first)
        if gate_level:
            codes = (0, 1, codes[-1] // 2, codes[-1])
        for code in codes:
            neighbors = (first[code] - 1, first[code], last[code], last[code] + 1)
            for coefficient in neighbors:
                left = rng.randrange(Q)
                right = rng.randrange(Q)
                shares = (left, right, (coefficient - left - right) % Q)
                await bus.check(shares, code, mode)
                cases += 1
    dut._log.info("Verified %d boundary transactions", cases)
