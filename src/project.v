/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

module tt_um_bluebrik1_pams_demo (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    localparam [2:0] RECEIVE = 3'd0;
    localparam [2:0] DIVIDE_SHARE = 3'd1;
    localparam [2:0] ADD_SHARE = 3'd2;
    localparam [2:0] START_ENDPOINT = 3'd3;
    localparam [2:0] DIVIDE_ENDPOINT = 3'd4;
    localparam [2:0] CHECK_ENDPOINT = 3'd5;
    localparam [12:0] Q = 13'd3329;

    reg [2:0] state;
    reg [2:0] byte_index;
    reg [11:0] remainder;
    reg [13:0] quotient;
    reg [3:0] bits_left;
    reg [13:0] switched_sum;
    reg [10:0] ciphertext;
    reg [1:0] mode;
    reg upper_endpoint;
    reg above_lower;
    reg frame_error;
    reg done;
    reg match;
    reg error;

    wire enabled = ena && rst_n;
    wire ready = enabled && state == RECEIVE;
    wire accept = ready && uio_in[0];
    assign uo_out = {4'b0, enabled && error, enabled && match,
                     enabled && done, ready};
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;
    wire _unused = &{1'b0, uio_in[7:1]};

    wire [11:0] share = {ui_in[3:0], remainder[7:0]};
    wire invalid_share = (|ui_in[7:4]) || ({1'b0, share} >= Q);
    wire [10:0] full_ciphertext = {ui_in[2:0], ciphertext[7:0]};
    wire invalid_ciphertext = (|ui_in[7:5]) ||
        (ui_in[4:3] == 2'd0 && (|full_ciphertext[10:4])) ||
        (ui_in[4:3] == 2'd1 && (|full_ciphertext[10:5])) ||
        (ui_in[4:3] == 2'd2 && full_ciphertext[10]);

    // b = (2c +/- 1) * 2^(13-d), reduced modulo 2^14.
    wire [11:0] odd_code = {ciphertext, 1'b1} -
        (upper_endpoint ? 12'd0 : 12'd2);
    reg [13:0] base;
    always @* begin
        case (mode)
            2'd0: base = {odd_code[4:0], 9'b0};
            2'd1: base = {odd_code[5:0], 8'b0};
            2'd2: base = {odd_code[10:0], 3'b0};
            default: base = {odd_code, 2'b0};
        endcase
    end

    // Q = 1 + 256 + 1024 + 2048. The residue's low two bits are zero.
    wire [11:0] neg_base_div4 = -base[13:2];
    wire [11:0] residue_div4 = neg_base_div4 + (neg_base_div4 << 8) +
        (neg_base_div4 << 10) + (neg_base_div4 << 11);

    // Restore the remainder one bit per cycle. The shares append 14 zeros.
    // The endpoint division starts above the bottom three bits.
    wire incoming_bit = state == DIVIDE_ENDPOINT && bits_left == 4'd3 &&
        residue_div4[0];
    wire [12:0] shifted_remainder = {remainder, incoming_bit};
    // Because remainder < Q, the difference is in [-Q, Q-1].
    wire [12:0] trial = shifted_remainder - Q;
    wire quotient_bit = !trial[12];

    // Endpoints are inclusive at the bottom and exclusive at the top.
    // Subtract one only from the upper endpoint to account for rounding.
    wire [3:0] correction = {1'b0, quotient[2:0]} - {3'b0, upper_endpoint};
    wire [13:0] boundary = base + {{10{correction[3]}}, correction};
    wire above_boundary = switched_sum >= boundary;
    // For d=11 and c=0 the lower integer endpoint is zero.
    wire wraps = (ciphertext == 11'd0) && (mode != 2'd3);
    wire inside_interval = wraps ? (above_lower || !above_boundary)
                                 : (above_lower && !above_boundary);

    always @(posedge clk) begin
        if (!rst_n || !ena) begin
            state <= RECEIVE;
            byte_index <= 3'd0;
            done <= 1'b0;
            match <= 1'b0;
            error <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            case (state)
                RECEIVE: if (accept) begin
                    byte_index <= byte_index + 3'd1;
                    if (byte_index == 3'd0) begin
                        switched_sum <= 14'd2;
                        frame_error <= 1'b0;
                        done <= 1'b0;
                        match <= 1'b0;
                        error <= 1'b0;
                    end

                    case (byte_index)
                        3'd0, 3'd2, 3'd4: remainder[7:0] <= ui_in;
                        3'd1, 3'd3, 3'd5: begin
                            frame_error <= frame_error || invalid_share;
                            remainder <= invalid_share ? 12'b0 : share;
                            quotient <= 14'b0;
                            bits_left <= 4'd14;
                            state <= DIVIDE_SHARE;
                        end
                        3'd6: ciphertext[7:0] <= ui_in;
                        3'd7: begin
                            frame_error <= frame_error || invalid_ciphertext;
                            ciphertext[10:8] <= ui_in[2:0];
                            mode <= ui_in[4:3];
                            upper_endpoint <= 1'b0;
                            state <= START_ENDPOINT;
                        end
                    endcase
                end

                DIVIDE_SHARE, DIVIDE_ENDPOINT: begin
                    remainder <= quotient_bit ? trial[11:0] : shifted_remainder[11:0];
                    quotient <= {quotient[12:0], quotient_bit};
                    bits_left <= bits_left - 4'd1;
                    if (bits_left == 4'd1)
                        state <= state == DIVIDE_SHARE ? ADD_SHARE : CHECK_ENDPOINT;
                end

                ADD_SHARE: begin
                    switched_sum <= switched_sum + quotient;
                    state <= RECEIVE;
                end

                START_ENDPOINT: begin
                    remainder <= {1'b0, residue_div4[11:1]};
                    quotient <= 14'b0;
                    bits_left <= 4'd3;
                    state <= DIVIDE_ENDPOINT;
                end

                CHECK_ENDPOINT: begin
                    if (!upper_endpoint) begin
                        above_lower <= above_boundary;
                        upper_endpoint <= 1'b1;
                        state <= START_ENDPOINT;
                    end else begin
                        match <= inside_interval && !frame_error;
                        error <= frame_error;
                        done <= 1'b1;
                        state <= RECEIVE;
                    end
                end

                default: begin
                    state <= RECEIVE;
                    byte_index <= 3'd0;
                    done <= 1'b0;
                    match <= 1'b0;
                    error <= 1'b0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
