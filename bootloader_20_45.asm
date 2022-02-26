         ORG     $0100
         LBRA    $0152
         JSR     $00,$013E
         CMPB    #$10           ; cmd 10 doesn't have a use yet
         lBEQ     $0104
         CMPB    #$20           ; cmd 20 is bank erase
         LBEQ    $0308
         CMPB    #$30
         lBEQ     $0104
         CMPB    #$40
         lBEQ     $0104
         CMPB    #$45           ; bulk memory dump
         lBEQ    $02AA
         BNE     $0104
         LDAA    $7C0C,Z        ; TX function
         ANDA    #$01
         BEQ     $0128
         STAB    $7C0F,Z
         LDD     #$0043         ; this is the TX delay interval
         JSR     $00,$014E
         RTS
         LDAA    $7C0D,Z        ; RX function
         ANDA    #$42
         CMPA    #$40
         BNE     $013E
         LDAB    $7C0F,Z
         RTS
         SUBD    #$0001         ; Delay function
         BNE     $014E
         RTS
         NOP                    ; Reader X byte
         ORP     #$00E0
         LDAB    #$0F
         TBZK
         LDZ     #$8000
         LDAB    #$00
         TBSK
         LDS     #$07F6
         CLRB
         TBEK
         TBYK
         LDAB    #$04
         TBXK
         LDX     #$8000
         LDD     #$0148
         STD     $7A00,Z
         BCLR    $7A21,Z,#$80
         LDD     #$00CF
         STD     $7A44,Z
         LDD     #$0405
         STD     $7A48,Z
         STD     $7A4C,Z
         LDD     #$68F0
         STD     $7A4A,Z
         LDD     #$70F0
         STD     $7A4E,Z
         LDD     #$FF88
         STD     $7A54,Z
         LDD     #$7830
         STD     $7A56,Z
         LDD     #$F881
         STD     $0814,Z
         LDD     $0812,Z
         ORD     #$0001
         STD     $0812,Z
         LDD     #$0000
         STD     $0818,Z
         BSETW   $0806,Z,#$FFFF
         BSETW   $0808,Z,#$03FF
         CLRD
         LDE     #$0824
         STD     E,Z
         ADDE    #$04
         CPE     #$0838
         BLS     $01EA
         CLR     $7920,Z
         BCLRW   $0860,Z,#$2000
         JSR     $00,$020A
         LDAB    #$22
         JSR     $00,$0128
         JMP     $00,$0104
         LDD     #$4088
         STD     $7C00,Z
         LDAA    #$06
         STAA    $7C04,Z
         LDAA    #$FE
         STAA    $7C05,Z
         LDAA    #$33
         STAA    $7C16,Z
         LDAA    #$F8
         STAA    $7C15,Z
         LDAA    #$FE
         STAA    $7C17,Z
         LDD     #$8108
         STD     $7C18,Z
         LDD     #$1000
         STD     $7C1A,Z
         LDD     #$0000
         STD     $7C1C,Z
         LDAA    #$00
         STAA    $7C1E,Z
         LDE     #$4242
         STE     $7D41,Z
         LDE     #$0202
         STE     $7D43,Z
         LDE     #$C202
         STE     $7D45,Z
         LDE     #$C242
         STE     $7D48,Z
         LDD     #$0100
         STD     $7D24,Z
         LDD     #$0202
         STD     $7C1C,Z
         JSR     $00,$0284
         RTS
         BCLR    $7C1F,Z,#$80
         BSET    $7C1A,Z,#$80
         CLRA
         DECA
         BEQ     $02A0
         BRCLR   $7C1F,Z,#$80,$028E
         BCLR    $7C1F,Z,#$80
         TSTA
         BRA     $02AA
         ORP     #$0100
         TPA
         LDAB    #$A5
         RTS
;  Command 45 / Memory dump:
         ldab    #$46            ; sequence will be:
                                 ; 0x45 0x07 0xFF 0xBF 0x00 0x40 request
                                 ; 0x46 0x07 0xFF 0xBF 0x00 0x40 response 
                                 ; and should return (in this example) 64 bytes from 0x7FFBF to 0x7FFFF
         jsr     $00,$0128       ; TX 0x46 as 0x45 acknowledge
         jsr     $00,$013E       ; RX
         tbxk                    ; RX Byte0 bank / XK e.g. 0x07
         jsr     $00,$0128       ; echo B0
         jsr     $00,$013E       ; RX Byte1 IX high byte, e.g. 0xFF
         stab    $0306
         jsr     $00,$0128       ; echo B1
         jsr     $00,$013E       ; RX Byte2 IX low , e.g. 0xBF
         stab    $0307           
         ldx     $0306           ; X is now XK:FFBF - we go up from here
         jsr     $00,$0128       ; echo B2 
         jsr     $00,$013E       ; RX Byte3 counter high byte, e.g. 0x00
         stab    $0156
         jsr     $00,$0128       ; echo B3
         jsr     $00,$013E       ; RX Byte4 counter low byte, e.g. 0x40
         stab    $0157
         lde     $0156           ; E is the byte counter
         jsr     $00,$0128       ; echo B4
;  Rd_xmit:
         ldab    0,X
         jsr     $00,$0128       ; Echo byte at address X
         aix     #$01            ; increment the address counter 
         tste    
         lbeq    $0104
         sube    #$01            ; decrement the byte counter
         bra     $02F2           ; if not zero loop
         nop                     ; this is the memory word we pull E from
; Command 20 / flash erase:
         ldab    #$21            ; echo 21 for 20 acknowledge
         jsr     $00,$0128
         jsr     $00,$013E       ; read bank 0x00 - 0x04
         jsr     $00,$0128       ; echo bank
         ldab    #$4
         tbxk
         ldx     #$0              ; 0x40000
         ldab    #$50
         jsr     $03A6           ; init GPT
         jsr     $03B2           ; check ready
         CMPB    #$00
         beq     $0344
         CMPB    #$01
         beq     $0350
         CMPB    #$02
         beq     $035C
         CMPB    #$03
         beq     $0368
         CMPB    #$04
         beq     $0374
         jsr     $00,$0128       ; B will contain error or success
         LBRA    $0104
   ; bank0
         ldab    #$4
         tbxk
         ldx     #$0000          ; 0x40000
         jsr     $0380          ; jump erase flash
   ; bank1
         ldab    #$4
         tbxk
         ldx     #$4000          ; 0x44000
         jsr     $0380          ; jump erase flash
   ; bank2
         ldab    #$4
         tbxk
         ldx     #$6000          ; 0x46000
         jsr     $0380          ; jump erase flash
   ; bank3
         ldab    #$4
         tbxk
         ldx     #$8000          ; 0x48000
         jsr     $0380          ; jump erase flash
   ; bank4
         ldab    #$6
         tbxk
         ldx     #$0000          ; 0x44000
         jsr     $0380           ; jump erase flash
; flash erase function
         ldd     #$20            ; CMD  Erase
         std     0,X             ; Block Address
         ldd     #$0D0           ; CMD Erase Resume/Erase Confirm
         std     0,X
         ldab    #$22            ; success
         BRA     $033C
; Set timeout
         ldd     $790A,Z         ; Timer Counter Register (TCNT)
         addd    #$F424
         std     $7916,Z         ; Timer Output Compare Register 2 (TOC2)
         ldab    $7922,Z         ; Timer Flag Register 1 (TFLG1)
         bclr    $7922,Z,#$10
         rts
; Init GPT
         clr     $791E,Z         ; Timer Control Register 1 (TCTL1)
         ldab    #$6              ; 256 divider
         stab    $7921,Z         ; Timer Mask Register 2 (TMSK2)
         rts
; Check flash CSM ready
         jsr     $0390           ; set timeout
         ldab    #$0A            ; 10 attempts with 256 divider ~ 10 seconds
         stab    $0306
  ; not ready         
         brclr   $7922,Z,#$10,$03D0 ; Check Flag Timeout
         jsr     $0390           ; Set tmeout - new attempt
         decw    $0306
         bne     $03D0
         ldab    #$80            ; return error "not ready"
         bra     $03E4           ; set error abd bail 
  ; check ready       
         ldd     #$70            ; CMD Read Status Register
         std     0,X
         ldd     0,X             ; Read Status registr
         andd    #$80            ; check Flag Ready
         beq     $03BC           ; no,repeat check flag
         ldd     0,X             ; else
         andd    #$78            ; Check for other errors in the status register.
  ; bail
         rts
