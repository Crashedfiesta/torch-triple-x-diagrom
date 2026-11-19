        .module torchdiag_v10_crtc
        .hd6303
        .area CODE (ABS)
        .org 0xC000

        ; --- TorchDiagROM v1.0 colour configuration ---
        ; Physical palette uses inverted RGB332 (see video.c).
        ; Colour 0 = background; colour 3 = font renderer foreground.
        ; Green $41 -> RGB #B6FFAA in the emulator's RGB332 conversion.
PAL_BACKGROUND .equ 0xFF       ; black
PAL_TEXT       .equ 0x41       ; pale mint green
PAL_UNUSED     .equ 0xFF       ; other two indices black


; TorchDiagROM v0.0.7b: VRAM test, beeps, 68010 VRAM bootstrap.
; Releases the 68010 after VRAM PASS; the 68010 then tests main DRAM. This is
; destructive to video RAM, and intended for emulator testing only.
;
; 6303 VRAM window $4000..$BFFF maps 32K bank 0 or 1,
; chosen by port 1 output-latch bit 2 (P1.2).
; We deliberately exclude $BFFF: emulator has a Caretaker-specific
; VRAM decay model on repeated reads of this address.
;
; Direct-page HD6303 internal RAM used here:
; $40 bank, $41 failure flag, $42:$43 failed SP address,
; $44 actual, $45 expected, $46:$47 scratch address, $48 mode.
; $49:$4A VRAM destination, $4B:$4C ROM source; $4E page count.
; $4D last observed 68010 progress counter (VRAM physical $0302).
;
; Speaker uses P2.1 DDR and timer output compare exactly as v0.0.2.

reset:
        sei
        lds     #0x00A9

        ldaa    #0x1A
        staa    *0x02           ; P1 latch, 68010 held in reset, bank 0
        ldaa    #0xFE
        staa    *0x00           ; P1 DDR
        ldaa    #0x1A
        staa    *0x02

        ldaa    #0x02
        staa    *0x01           ; P2.1 output enables speaker
        clra
        staa    *0x08           ; Timer status/control

        .byte   0x7F,0x00,0x41  ; CLR $0041 (extended)           ; Failure flag = 0
        .byte   0x7F,0x00,0x40  ; CLR $0040 (extended)           ; Bank 0

        ; Run full test on bank 0.
        jsr     test_bank
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     failed

        ; Leave bank 0 filled with A5; later verify bank independence.
        ldab    #0xA5
        jsr     fill_bank

        ldaa    #0x01
        staa    *0x40           ; Bank 1
        ldaa    #0x1E
        staa    *0x02           ; Bank 1; P1.3 remains set (host reset)
        jsr     test_bank
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     failed

        ; Leave bank 1 with 5A, distinctly different from bank 0.
        ldab    #0x5A
        jsr     fill_bank
        jsr     verify_bank
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     failed

        ; Go back and verify bank 0 was not affected by bank 1.
        .byte   0x7F,0x00,0x40  ; CLR $0040 (extended)
        ldaa    #0x1A
        staa    *0x02
        ldab    #0xA5
        jsr     verify_bank
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     failed

passed:
        jmp     stage2

failed:
        ; ONE long tone, pause, repeat = VRAM FAIL.
        ; Does NOT attempt to release the 68010.
        jsr     long_chirp
        jsr     long_gap
        bra     failed

; All VRAM tests have passed. Announce that fact ONCE, independently of
; whether the host CPU can start. The 6303 is still running from EPROM.
stage2:
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     long_gap

        ; v1.0: program the 6845 with Caretaker's working display timing.
        ; Do this only after VRAM PASS, preserving beep-only diagnosis if
        ; the early video memory test fails. HD6303 still holds 68010 reset.
        jsr     crtc_init

        ; Explicitly initialise palette RAM via the HD6303.
        ; Keep the v0.9 pale-green-on-black display unchanged.
        ldaa    #PAL_BACKGROUND
        staa    0x0500         ; pixel colour index 0: background
        ldaa    #PAL_UNUSED
        staa    0x0501         ; pixel index 1
        staa    0x0502         ; pixel index 2
        ldaa    #PAL_TEXT
        staa    0x0503         ; pixel index 3: text foreground

        ; Clear display VRAM BEFORE installing 68010 code.
        ; This is destructive but safe here: the 6303 executes from EPROM.
        ; Never clear VRAM after the 68010 has been released!
        ldaa    #0x1A              ; bank 0, host held reset
        staa    *0x02
        ldab    #0x00
        jsr     fill_bank          ; $4000..$BFFE bank 0
        ldaa    #0x1E              ; bank 1, host held reset
        staa    *0x02
        ldab    #0x00
        jsr     fill_bank          ; $4000..$BFFE bank 1
        ldaa    #0x1A              ; return to bank 0
        staa    *0x02

        ; Clear both mailbox bytes before 68010 release.
        ; $4300: alive ACK ($A5), $4301: RAM status.
        clra
        staa    0x4300
        staa    0x4301
        staa    0x4302          ; 68010 progress heartbeat

        ; Copy 68010 executable code into tested bank-1 VRAM $8000-$87FF.
        ; The code is not loaded into the active visible text rows.
        ldaa    #0x1E              ; select bank 1, hold host reset
        staa    *0x02
        ldx     #0xD000            ; ROM source: assembled 68010 code
        stx     *0x4B
        ldx     #0x4000            ; bank 1 window -> physical $8000
        stx     *0x49
        ldaa    #0x08              ; 8 pages = 2048 bytes
        staa    *0x4E
        jsr     copy_pages

        ldx     #0xD000
        stx     *0x4B
        ldx     #0x4000
        stx     *0x49
        ldaa    #0x08
        staa    *0x4E
        jsr     verify_pages

        ; Original Torch font: 95 glyphs * 8 bytes = 760 bytes.
        ; Copy padded 768 bytes to physical VRAM $9000-$92FF.
        ldx     #0xD800
        stx     *0x4B
        ldx     #0x5000
        stx     *0x49
        ldaa    #0x03
        staa    *0x4E
        jsr     copy_pages
        ldx     #0xD800
        stx     *0x4B
        ldx     #0x5000
        stx     *0x49
        ldaa    #0x03
        staa    *0x4E
        jsr     verify_pages

        ; Reset vectors must be visible to the 68010 at physical $0000.
        ; Copy 12 bytes from ROM $DB00 into bank-0 VRAM $0000..$000B.
        ldaa    #0x1A              ; bank 0, host STILL held reset
        staa    *0x02
        ldx     #0xDB00
        stx     *0x4B
        ldx     #0x4000
        stx     *0x49
        ldab    #0x0C
        jsr     copy_bytes
        ldx     #0xDB00
        stx     *0x4B
        ldx     #0x4000
        stx     *0x49
        ldab    #0x0C
        jsr     verify_bytes

        ; Tell emulator to expose the VRAM framebuffer in dark-blue mode.
        ; This is an existing Caretaker mailbox behaviour in triplex.c;
        ; it is not a C-side fake character or graphics injection.
        ; It is emulator-specific: on physical hardware we'll initialise
        ; the CRTC and palette separately before expecting visible text.
        ldaa    #0x0F
        staa    0x43F0
        ldaa    0x43F0          ; emulator switches to framebuffer mode on READ

        ; P1.3 1 -> 0 releases the 68010, bank remains zero.
        ldaa    #0x12
        staa    *0x02

        ; Wait for the 68010 to write $A5 into VRAM physical $0300.
        ; Bounded polling: if no response, we still have the 6303/beeper.
        ldx     #0xFFFF
wait_host:
        ldaa    0x4300
        cmpa    #0xA5
        beq     host_ack
        dex
        bne     wait_host

host_timeout:
        ; LONG, SHORT, SHORT = 68010 has not acknowledged.
        ; Loop final stage only (VRAM PASS chirps were played once).
        jsr     long_chirp
        jsr     short_gap
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     long_gap
        bra     host_timeout

host_ack:
        ; THREE short chirps ONCE = 68010 has executed in VRAM.
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     long_gap

        ; $4301 remains zero while the 68010 tests RAM.
        ; The delay while sounding the three chirps is ample for the
        ; tiny 68010 test in normal operation, but also poll safely.
        .byte   0x7F,0x00,0x4D ; CLR $004D (extended), last progress
        ldx     #0xFFFF
wait_ram:
        ldaa    0x4301
        cmpa    #0x5A       ; completed, all checks passed
        beq     ram_pass
        cmpa    #0xE1       ; memory data mismatch
        beq     ram_data_fail
        cmpa    #0xE2       ; 68010 bus-error exception
        beq     ram_bus_fail
        ; The 1 MB test takes considerably longer than the old 4 KB
        ; test. A changing progress byte resets the timeout watchdog.
        ldaa    0x4302
        cmpa    *0x4D
        beq     ram_no_progress
        staa    *0x4D
        ldx     #0xFFFF
        bra     wait_ram
ram_no_progress:
        dex
        bne     wait_ram
        jmp     ram_timeout

ram_pass:
        ; FOUR short beeps repeating = full 1 MB DRAM PASS.
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     short_gap
        jsr     chirp
        jsr     long_gap
        bra     ram_pass

ram_data_fail:
        ; TWO long beeps repeating = RAM readback mismatch.
        jsr     long_chirp
        jsr     short_gap
        jsr     long_chirp
        jsr     long_gap
        bra     ram_data_fail

ram_bus_fail:
        ; TWO long, one short = bus error on RAM access.
        jsr     long_chirp
        jsr     short_gap
        jsr     long_chirp
        jsr     short_gap
        jsr     chirp
        jsr     long_gap
        bra     ram_bus_fail

ram_timeout:
        ; THREE long beeps = 68010 acknowledged but never finished RAM test.
        jsr     long_chirp
        jsr     short_gap
        jsr     long_chirp
        jsr     short_gap
        jsr     long_chirp
        jsr     long_gap
        bra     ram_timeout

; ROM->VRAM copy: *$4B ROM source, *$49 window destination,
; *$4E page count, selected bank is already set. 6303 executes ROM.
copy_pages:
copy_page:
        ldab    #0x00            ; 256 iterations
        jsr     copy_bytes
        ldaa    *0x4E
        deca
        staa    *0x4E
        bne     copy_page
        rts

verify_pages:
verify_page:
        ldab    #0x00            ; 256 iterations
        jsr     verify_bytes
        ldaa    *0x4E
        deca
        staa    *0x4E
        bne     verify_page
        rts

copy_bytes:
copy_byte:
        ldx     *0x4B
        ldaa    0,x
        inx
        stx     *0x4B
        ldx     *0x49
        staa    0,x
        inx
        stx     *0x49
        decb
        bne     copy_byte
        rts

verify_bytes:
verify_byte:
        ldx     *0x4B
        ldaa    0,x
        inx
        stx     *0x4B
        ldx     *0x49
        cmpa    0,x
        bne     verify_bad
        inx
        stx     *0x49
        decb
        bne     verify_byte
        rts
verify_bad:
        jmp     host_timeout     ; copied program/font/vector mismatch

; Test the selected 32K VRAM bank.
; Four byte patterns across the entire bank, then two address patterns.
test_bank:
        ldab    #0x00
        jsr     run_pattern
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     tb_done
        ldab    #0xFF
        jsr     run_pattern
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     tb_done
        ldab    #0x55
        jsr     run_pattern
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     tb_done
        ldab    #0xAA
        jsr     run_pattern
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     tb_done

        .byte   0x7F,0x00,0x48  ; CLR $0048 (extended)           ; Address high byte
        jsr     address_pattern
        .byte   0x7D,0x00,0x41  ; TST $0041 (extended)
        bne     tb_done
        ldaa    #0x01
        staa    *0x48           ; Address low byte
        jsr     address_pattern
tb_done:
        rts

; B contains pattern, X points to current 6303 window address.
run_pattern:
        jsr     fill_bank
        jsr     verify_bank
        rts

; Fill $4000..$BFFE inclusive; do NOT touch $BFFF.
fill_bank:
        ldx     #0x4000
fb_loop:
        stab    0,x
        inx
        cpx     #0xBFFF
        bne     fb_loop
        rts

verify_bank:
        ldx     #0x4000
vb_loop:
        cmpb    0,x
        bne     data_failure
        inx
        cpx     #0xBFFF
        bne     vb_loop
        rts

data_failure:
        stx     *0x42
        stab    *0x45           ; expected
        ldaa    0,x
        staa    *0x44           ; actual
        ldaa    #0x01
        staa    *0x41
        rts

; Write the byte of the WINDOW ADDRESS to every location, then check
; the full bank. Mode $48: 0 => high address byte, 1 => low byte.
; Two different patterns help reveal address decoder aliasing.
address_pattern:
        ldx     #0x4000
ap_fill:
        stx     *0x46
        ldaa    *0x46
        .byte   0x7D,0x00,0x48  ; TST $0048 (extended)
        beq     ap_fill_store
        ldaa    *0x47
ap_fill_store:
        staa    0,x
        inx
        cpx     #0xBFFF
        bne     ap_fill

        ldx     #0x4000
ap_verify:
        stx     *0x46
        ldaa    *0x46
        .byte   0x7D,0x00,0x48  ; TST $0048 (extended)
        beq     ap_compare
        ldaa    *0x47
ap_compare:
        cmpa    0,x
        bne     address_failure
        inx
        cpx     #0xBFFF
        bne     ap_verify
        rts

address_failure:
        stx     *0x42
        staa    *0x45           ; expected address-dependent byte
        ldaa    0,x
        staa    *0x44           ; actual
        ldaa    #0x01
        staa    *0x41
        rts

; --------------------------------------------------------------------
; v1.0: Initial HD6845 CRTC timing, captured from original Caretaker.
; 6303 $0400 = register select, $0401 = register data.
; The first Caretaker pass uses R1=$5A and R2=$67; it then changes
; those to R1=$5C and R2=$68. Use the settled timing here.
; R12/R13 and R14/R15 are CRTC address units, not VRAM byte offsets.
; Keep all sixteen writes in the original order, including cursor regs.
; --------------------------------------------------------------------
crtc_init:
        ldx     #crtc_values
        clrb                     ; R0 .. R15
crtc_next:
        stab    0x0400           ; Select 6845 register B
        ldaa    0,x              ; Load Caretaker's register value
        staa    0x0401           ; Program 6845 register
        inx
        incb
        cmpb    #0x10
        bne     crtc_next
        rts

crtc_values:
        .byte   0x7F            ; R0  Horizontal total
        .byte   0x5C            ; R1  Horizontal displayed (settled)
        .byte   0x68            ; R2  Horizontal sync position (settled)
        .byte   0x4C            ; R3  Sync widths
        .byte   0x26            ; R4  Vertical total
        .byte   0x00            ; R5  Vertical total adjust
        .byte   0x20            ; R6  Vertical displayed (32 rows)
        .byte   0x22            ; R7  Vertical sync position
        .byte   0x04            ; R8  Mode / interlace / skew
        .byte   0x07            ; R9  Maximum raster address (8 scanlines)
        .byte   0x00            ; R10 Cursor start
        .byte   0x00            ; R11 Cursor end
        .byte   0x00            ; R12 Display start high
        .byte   0x01            ; R13 Display start low
        .byte   0x00            ; R14 Cursor high
        .byte   0x01            ; R15 Cursor low

; Exactly the known-good v0.0.2 timer/speaker routines.
chirp:
        ldx     #0x00F0
chirp_loop:
        ldaa    *0x08
        eora    #0x01
        staa    *0x08
        jsr     timer_tick
        dex
        bne     chirp_loop
        rts

long_chirp:
        ldx     #0x0600
long_chirp_loop:
        ldaa    *0x08
        eora    #0x01
        staa    *0x08
        jsr     timer_tick
        dex
        bne     long_chirp_loop
        rts

short_gap:
        ldx     #0x0140
short_loop:
        jsr     quiet_tick
        dex
        bne     short_loop
        rts

long_gap:
        ldx     #0x0400
long_loop:
        jsr     quiet_tick
        dex
        bne     long_loop
        rts

quiet_tick:
        ldaa    *0x08
        anda    #0xFE
        staa    *0x08
        jsr     timer_tick
        rts

timer_tick:
        ldd     *0x09
        addd    #0x0800
        std     *0x0B
wait_ocf:
        ldaa    *0x08
        bita    #0x40
        beq     wait_ocf
        rts

; Put each 16-bit vector on its own line to avoid ASxxxx listing
; continuation-row parsing problems. Last vector ($FFFE) = reset.
        .org 0xFFF0
        .word   0xC000
        .word   0xC000
        .word   0xC000
        .word   0xC000
        .word   0xC000
        .word   0xC000
        .word   0xC000
        .word   0xC000
