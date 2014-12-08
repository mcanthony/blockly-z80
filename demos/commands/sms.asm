;==============================================================
; SMS defines
;==============================================================
VDPControl:	equ $bf
VDPData: 	equ $be
VRAMWrite:	equ $4000
CRAMWrite:	equ $c000	
RAMStart: 	equ $c000

;==============================================================
; RAM defines
;==============================================================
hw_sprites_y:		equ RAMStart + 0
hw_sprites_y_len:	equ 64
hw_sprites_xc:		equ hw_sprites_y + hw_sprites_y_len
hw_sprites_xc_len:	equ 128

UsrRAMStart:		equ hw_sprites_xc + hw_sprites_xc_len

	org 0000h
	
;==============================================================
; Boot section
;==============================================================
	di              ; disable interrupts
	im 1            ; Interrupt mode 1
	jp setup         ; jump to setup routine

	; org $0066 ; multiple orgs not supported by bitz80... please, don't press pause... ^_^

;==============================================================
; Setup
;==============================================================
setup:
	ld sp, $dff0

	;==============================================================
	; Set up VDP registers
	;==============================================================
	ld hl,VDPInitData
	ld b,VDPInitDataEnd-VDPInitData
	ld c,VDPControl
	otir

	;==============================================================
	; Clear VRAM
	;==============================================================
	; 1. Set VRAM write address to $0000
	ld hl,$0000 | VRAMWrite
	call SetVDPAddress
	; 2. Output 16KB of zeroes
	ld bc,$4000     ; Counter for 16KB of VRAM
ClearVRAM_Loop:  
	xor a
	out (VDPData),a ; Output to VRAM address, which is auto-incremented after each write
	dec bc
	ld a,b
	or c
	jr nz, ClearVRAM_Loop

	;==============================================================
	; Load palette
	;==============================================================
	; 1. Set VRAM write address to CRAM (palette) address 0
	ld hl,$0000 | CRAMWrite
	call SetVDPAddress
	; 2. Output colour data
	ld hl,PaletteData
	ld bc,PaletteDataEnd-PaletteData
	call CopyToVDP
	
	;==============================================================
	; Load tiles (font)
	;==============================================================
	; 1. Set VRAM write address to tile index 0
	ld hl,$0000 | VRAMWrite
	call SetVDPAddress
	; 2. Output tile data
	ld hl,FontData              ; Location of tile data
	ld bc,FontDataEnd-FontData  ; Counter for number of bytes to write
	call Copy1bppToVDP

	;==============================================================
	; Load orc tiles
	;==============================================================
	; 1. Set VRAM write address to tile index 256
	ld hl,$2000 | VRAMWrite
	call SetVDPAddress
	; 2. Output tile data
	ld hl,OrcData              ; Location of tile data
	ld bc,OrcDataEnd-OrcData  ; Counter for number of bytes to write
	call CopyToVDP

	;==============================================================
	; Turn screen on
	;==============================================================
	ld a,01000010b
;          ||||||`- Zoomed sprites -> 16x16 pixels
;          |||||`-- Doubled sprites -> 2 tiles per sprite, 8x16
;          ||||`--- Mega Drive mode 5 enable
;          |||`---- 30 row/240 line mode
;          ||`----- 28 row/224 line mode
;          |`------ VBlank interrupts
;          `------- Enable display
	out (VDPControl),a
	ld a,$81
	out (VDPControl),a

; Infinite loop to stop program
; Infinite_Loop :  jr Infinite_Loop

; Show a sprite
	; Left side
	ld a, 96
	ld (hw_sprites_y), a
	ld (hw_sprites_xc), a
	ld a, 0
	ld (hw_sprites_xc+1), a
	; Right side
	ld a, 96
	ld (hw_sprites_y+1), a
	ld a, 96 + 8
	ld (hw_sprites_xc+2), a
	ld a, 2
	ld (hw_sprites_xc+3), a
	; Sprite list terminator
	ld a, 208
	ld (hw_sprites_y+2), a
	call UpdateSprites
	

; call main program
	; Set VRAM write address to tilemap index 0
	ld hl,$3800 | VRAMWrite
	call SetVDPAddress

	jp MAIN
	
;==============================================================
; Helper functions
;==============================================================

SetVDPAddress:
; Sets the VDP address
; Parameters: hl = address
	push af
		ld a,l
		out (VDPControl),a
		ld a,h
		out (VDPControl),a
	pop af
	ret

	
CopyToVDP:
; Copies data to the VDP
; Parameters: hl = data address, bc = data length
; Affects: a, hl, bc
CopyToVDP_Loop:  
	ld a,(hl)    ; Get data byte
	out (VDPData),a
	inc hl       ; Point to next letter
	dec bc
	ld a,b
	or c
	jr nz, CopyToVDP_Loop
	ret

	
Copy1bppToVDP:
; Copies 1bpp char data to the VDP
; Parameters: hl = data address, bc = data length
; Affects: a, hl, bc
Copy1bppToVDP_Loop:  
	ld a,(hl)    ; Get data byte
	out (VDPData),a
	xor a		; pad the next 3 bytes
	out (VDPData),a
	out (VDPData),a
	out (VDPData),a
	inc hl       ; Point to next byte
	dec bc
	ld a,b
	or c
	jr nz, Copy1bppToVDP_Loop
	ret


;====================================
; HL *= DE
; Based on Z88DK runtime library
;====================================
Multiply:
		ld      b,16
		ld      a,h
		ld      c,l
		ld      hl,0
Multiply_Loop:
		add     hl,hl
		rl      c
		rla                  
		jr      nc, Multiply_Inner_Loop
		add     hl,de
Multiply_Inner_Loop:
		djnz    Multiply_Loop
		ret

;====================================
; hl = de/hl   de=de % hl
; Based on Z88DK runtime library
;====================================
Divide:
; Check for dividing by zero beforehand
		ld      a,h
		or      l
		ret     z
		ex      de,hl
;First have to obtain signs for quotient and remainder
		ld      a,h     ;dividend
		and     128
		ld      b,a     ;keep it safe
		jr      z,l_div0
;if -ve make into positive number!
		sub     a
		sub     l
		ld      l,a
		sbc     a,a
		sub     h
		ld      h,a
l_div0:
		ld      a,d     ;divisor
		and     128
		xor     b       
		ld      c,a     ;keep it safe (Quotient)
		bit     7,d
		jr      z,l_div01
		sub     a
		sub     e
		ld      e,a
		sbc     a,a
		sub     d
		ld      d,a
l_div01:
;Check for dividing by zero...
		ex      de,hl
		ld      a,h
		or      l
		ret     z       ;return hl=0, de=divisor
		ex      de,hl
		push    bc      ;keep the signs safe
;Now, we have two positive numbers so can do division no problems..
		ld      a,16    ;counter
		ld      b,h     ;arg1
		ld      c,l
		ld      hl,0    ;res1
; hl=res1 de=arg2 bc=arg1
		and     a
l_div1:
		rl      c       ;arg1 << 1 -> arg1
		rl      b
		rl      l       ;res1 << 1 -> res1
		rl      h
		sbc     hl,de   ;res1 - arg2 -> res1
		jr      nc,l_div2
		add     hl,de   ;res1 + arg2 -> res1
l_div2:
		ccf
		dec     a
		jr      nz,l_div1
		rl      c       ;arg1 << 1 -> arg1
		rl      b
;Have to return arg1 in hl and res1 in de
		ld      d,b
		ld      e,c
;Now do the signs..
		pop     bc      ;c holds quotient, b holds remainder
;de holds quotient, hl holds remainder
		ld      a,c
		call    dosign  ;quotient
		ld      a,b
		ex      de,hl   ;remainder (into de)
;Do the signs - de holds number to sign, a holds sign
dosign:
		and     128
		ret     z       ;not negative so okay..
		sub     a
		sub     e
		ld      e,a
		sbc     a,a
		sub     d
		ld      d,a
		ret

		
;====================================
; Print text
;====================================
text_print:
	ld a,(hl)
	or a
	jr z, text_print_end
	sub 32
	out (VDPData),a
	xor a
	out (VDPData),a
	inc hl
	jr text_print
text_print_end:
	ret

;====================================
; Print number
;====================================
number_print:
	xor a
	push af		; a = 0 will be used as a terminator
	; initially, hl contains the number
number_print_digits:
	ex	de, hl	; Now, DE contains the number
	ld	hl, 10	; It will be divided by 10
	call Divide	; Now, DE contains the digit, and HL contains the part that hasn't been processed, yet.
	
	ld a, e
	add a, 48-32 ; Adds '0'
	push af		; Saves the digit for later (TODO: Should optimize this to use just one byte per digit)
	
	ld a, l
	or h
	jr z, number_print_digits_done
	jr number_print_digits	; There are still digits to print
number_print_digits_done:
	
number_print_output_loop:
	pop af
	or a
	jr z, number_print_output_loop_done		
	out (VDPData),a
	xor a
	out (VDPData),a
	jr number_print_output_loop
number_print_output_loop_done:
	ret

;==============================================================
; Sets the sprites' positions/attributes
;==============================================================	
UpdateSprites:
	;vdp set addr (Y table)
	xor	a
	out	($bf), a
	ld	a, $7f
	out	($bf), a
	
	; Outputs Y table
	ld	hl, hw_sprites_y
	ld	bc, $40BE	; 64 bytes to $be
	otir			; Output table

	;vdp set addr (X/Tile table)
	ld	a, $80
	out	($bf), a
	ld	a, $7f
	out	($bf), a
	
	; Outputs XA table
	ld	hl, hw_sprites_xc
	ld	bc, $80BE	; 128 bytes to $be
	otir			; Output table
	ret
