; TorchDiagROM v1.0 experimental: separately test main and Limpet DRAM from VRAM.
; Main RAM is NOT required for any of this code or stack.
;
; 68010 physical VRAM map:
;  $0000-$000B  reset SSP, PC and BERR vector
;  $0300-$0302  ACK, result, heartbeat mailbox to 6303
;  $0310-$0324  hex scratch, first-failure report, and test-region flag
;  $03F0        legacy emulator-only framebuffer-state trigger
;  $2000-$7FFF  DISPLAY TEXT ONLY (scanlines 32-127)
;  $8000-$87FF  68010 executable (bank 1)
;  $9000-$92FF  original Torch 8x8 font (bank 1)
;  $F000-$F7EF  68010 supervisor stack (bank 1)
;  $F7F0       initial SSP (stack grows down)
;
; Colour: $FF generates 4 bright 2-bit pixels per framebuffer byte.
; The CRTC is not yet programmed here; the 6303 uses an existing
; emulator-specific $43F0 readback to expose the framebuffer.
;
        org     $00000000
        dc.l    $0000F7F0        ; Initial supervisor stack, in bank 1
        dc.l    start            ; Reset PC points to bank-1 code
        dc.l    bus_error        ; Vector 2 (BERR) remains in VRAM

        org     $00008000
start:
        move.b  #$A5,$00000300
        clr.b   $00000301
        clr.b   $00000302
        clr.b   $00000324       ; 0=main DRAM, 1=Limpet DRAM
        bsr     draw_screen

        ; Test main 1 MB first, then the optional Limpet expansion.
        ; The diagnostic itself remains entirely in VRAM.
        movea.l #$00100000,a6
        bsr     test_1mb
        lea     msg_ram_pass(pc),a0
        movea.l #$00005002,a1
        bsr     print_string

        move.b  #1,$00000324
        lea     msg_limpet_testing(pc),a0
        movea.l #$00005802,a1
        bsr     print_string
        movea.l #$00200000,a6
        bsr     test_1mb
        lea     msg_limpet_pass(pc),a0
        movea.l #$00005802,a1
        bsr     print_string

ram_success:
        move.b  #$5A,$00000301
finished:
        bra.s   finished

; Test 1 MB at A6.  No writes outside [A6, A6+$0FFFFF].
; All 68010 code, stack, font, vectors and results remain in VRAM.
test_1mb:
        move.l  #$5A5AA5A5,d1
        bsr     fill_1mb
        bsr     verify_1mb

        move.l  #$A5A55A5A,d1
        bsr     fill_1mb
        bsr     verify_1mb

        movea.l a6,a2
        move.w  #255,d4
next_walk_block:
        moveq   #1,d1
walk_one:
        movea.l a2,a5
        move.l  d1,(a2)
        move.l  (a2),d2
        cmp.l   d1,d2
        bne     ram_failure
        add.l   d1,d1
        bne     walk_one
        adda.l  #4096,a2
        addq.b  #1,$00000302
        dbf     d4,next_walk_block
        rts

ram_failure:
        ; A5=precise tested address, D1=expected, D2=actual.
        ; Store everything before the renderer overwrites registers.
        move.l  a5,$00000314
        move.l  d1,$00000318
        move.l  d2,$0000031C
        eor.l   d1,d2
        move.l  d2,$00000320
        tst.b   $00000324
        beq.s   .main_data_failure
        lea     msg_limpet_fail(pc),a0
        movea.l #$00005802,a1
        bra.s   .show_data_failure
.main_data_failure:
        lea     msg_ram_fail(pc),a0
        movea.l #$00005002,a1
.show_data_failure:
        bsr     print_string
        bsr     report_data_fault
        move.b  #$E1,$00000301
failure_loop:
        bra.s   failure_loop

bus_error:
        ; The BERR vector, stack and handler are in VRAM.
        ; Accessing DRAM has failed: do NOT retry that access.
        ; A5 is set immediately BEFORE every DRAM read or write.
        move.l  a5,$00000314
        tst.b   $00000324
        beq.s   .main_bus_failure
        lea     msg_limpet_berr(pc),a0
        movea.l #$00005802,a1
        bra.s   .show_bus_failure
.main_bus_failure:
        lea     msg_ram_berr(pc),a0
        movea.l #$00005002,a1
.show_bus_failure:
        bsr     print_string
        bsr     report_bus_fault
        move.b  #$E2,$00000301
bus_error_loop:
        bra.s   bus_error_loop

fill_1mb:
        movea.l a6,a0
        move.w  #255,d4
fill_block:
        move.w  #1023,d0
fill_loop:
        movea.l a0,a5
        move.l  d1,(a0)
        adda.l  #4,a0
        dbf     d0,fill_loop
        addq.b  #1,$00000302
        dbf     d4,fill_block
        rts

verify_1mb:
        movea.l a6,a0
        move.w  #255,d4
verify_block:
        move.w  #1023,d0
verify_loop:
        movea.l a0,a5
        move.l  (a0),d2
        cmp.l   d1,d2
        bne     ram_failure
        adda.l  #4,a0
        dbf     d0,verify_loop
        addq.b  #1,$00000302
        dbf     d4,verify_block
        rts

; Display the recorded 32-bit values. Each row has independent VRAM.
; In particular, these writes never enter code at $8000+, font at
; $9000+, stack at $F000+, or vectors/mailbox at $0000-$03FF.
report_data_fault:
        lea     msg_addr(pc),a0
        movea.l #$00006002,a1
        bsr     print_string
        move.l  $00000314,d5
        bsr     print_hex32

        lea     msg_expected(pc),a0
        movea.l #$00006802,a1
        bsr     print_string
        move.l  $00000318,d5
        bsr     print_hex32

        lea     msg_actual(pc),a0
        movea.l #$00007002,a1
        bsr     print_string
        move.l  $0000031C,d5
        bsr     print_hex32

        lea     msg_xor(pc),a0
        movea.l #$00007802,a1
        bsr     print_string
        move.l  $00000320,d5
        bsr     print_hex32
        rts

report_bus_fault:
        lea     msg_addr(pc),a0
        movea.l #$00006002,a1
        bsr     print_string
        move.l  $00000314,d5
        bsr     print_hex32
        lea     msg_berr_detail(pc),a0
        movea.l #$00006802,a1
        bsr     print_string
        rts

; D5 = unsigned long to print, A1 = framebuffer cursor.
; Produces exactly eight uppercase hex digits, including leading zeros.
; print_string clobbers D0/D2/D3/D4 and A0/A2/A3/A4, but not D5/D6.
print_hex32:
        moveq   #7,d6
.hex_next:
        rol.l   #4,d5
        move.l  d5,d0
        andi.w  #$000F,d0
        lea     hex_digits(pc),a0
        move.b  (a0,d0.w),d0
        move.b  d0,$00000310
        clr.b   $00000311
        lea     $00000310,a0
        bsr     print_string
        dbf     d6,.hex_next
        rts

hex_digits:
        dc.b    "0123456789ABCDEF"
        even

; Full text screen. Each framebuffer scanline is 256 bytes; one text
; row is 8 scanlines = 2048 bytes. We draw only scanlines 32..87.
draw_screen:
        lea     msg_title(pc),a0
        movea.l #$00002002,a1    ; scanline 32
        bsr     print_string
        lea     msg_rule(pc),a0
        movea.l #$00002802,a1    ; scanline 40
        bsr     print_string
        lea     msg_6303(pc),a0
        movea.l #$00003802,a1    ; scanline 56
        bsr     print_string
        lea     msg_vram(pc),a0
        movea.l #$00004002,a1    ; scanline 64
        bsr     print_string
        lea     msg_68010(pc),a0
        movea.l #$00004802,a1    ; scanline 72
        bsr     print_string
        lea     msg_testing(pc),a0
        movea.l #$00005002,a1    ; scanline 80
        bsr     print_string
        lea     msg_limpet_wait(pc),a0
        movea.l #$00005802,a1    ; scanline 88
        bsr     print_string
        rts

; print_string: A0 -> zero-terminated ASCII; A1 -> first framebuffer
; byte of text row. Preserve no general registers (callers here know).
; Glyphs are original ERMA font data, ASCII $20..$7E, 8 bytes each.
; Each glyph row expands 8 one-bit pixels to two 2bpp VRAM bytes.
; All writes constrained by caller to $2002..$77FF.
print_string:
.next:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .done
        cmpi.b  #$20,d0
        blo.s   .next
        cmpi.b  #$7E,d0
        bhi.s   .next
        subi.w  #$20,d0
        lsl.w   #3,d0
        movea.l #$00009000,a2
        adda.w  d0,a2
        movea.l a1,a3
        moveq   #7,d2
.pixel_row:
        moveq   #0,d3
        move.b  (a2)+,d3
        move.w  d3,d4
        lsr.w   #4,d4
        andi.w  #$000F,d4
        lea     expand4(pc),a4
        move.b  (a4,d4.w),(a3)+
        andi.w  #$000F,d3
        move.b  (a4,d3.w),(a3)+
        adda.w  #254,a3       ; next scanline, same X
        dbf     d2,.pixel_row
        addq.l  #2,a1         ; next character: 8 pixels = 2 bytes
        bra.s   .next
.done:
        rts

; Expand a 4-bit font nibble to four 2-bit pixels (0 or 3).
expand4:
        dc.b    $00,$03,$0C,$0F,$30,$33,$3C,$3F
        dc.b    $C0,$C3,$CC,$CF,$F0,$F3,$FC,$FF

msg_title:      dc.b "TORCH TRIPLE X DIAGNOSTICS V1.0",0
msg_rule:       dc.b "================================",0
msg_6303:      dc.b "HD6303 SERVICE PROCESSOR  OK",0
msg_vram:      dc.b "VIDEO RAM 64KB            PASS",0
msg_68010:     dc.b "68010 BOOTSTRAP           PASS",0
msg_testing:   dc.b "MAIN RAM 1024KB           TESTING",0
msg_ram_pass:  dc.b "MAIN RAM 1024KB           PASS   ",0
msg_ram_fail:  dc.b "MAIN RAM 1024KB           FAIL   ",0
msg_ram_berr:  dc.b "MAIN RAM 1024KB           BERR   ",0
msg_limpet_wait:    dc.b "LIMPET RAM 1024KB         WAIT   ",0
msg_limpet_testing: dc.b "LIMPET RAM 1024KB         TESTING",0
msg_limpet_pass:    dc.b "LIMPET RAM 1024KB         PASS   ",0
msg_limpet_fail:    dc.b "LIMPET RAM 1024KB         FAIL   ",0
msg_limpet_berr:    dc.b "LIMPET RAM 1024KB         BERR   ",0
msg_addr:      dc.b "FAULT ADDRESS : $",0
msg_expected:  dc.b "EXPECTED      : $",0
msg_actual:    dc.b "ACTUAL        : $",0
msg_xor:       dc.b "XOR MASK      : $",0
msg_berr_detail: dc.b "BUS ERROR - NO DATA READBACK",0
        even
