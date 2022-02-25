         ORG     $0100
         LBRA    $0150
         JSR     $00,$0136
         CMPB    #$10           ; cmd 10-40 don't have a use yet
         BEQ     $0104
         CMPB    #$20
         BEQ     $0104
         CMPB    #$30
         BEQ     $0104
         CMPB    #$40
         BEQ     $0104
         CMPB    #$45
         lBEQ    $02A2
         BNE     $0104
         LDAA    $7C0C,Z        ; TX function
         ANDA    #$01
         BEQ     $0120
         STAB    $7C0F,Z
         LDD     #$0043         ; this is the TX delay interval
         JSR     $00,$0146
         RTS
         LDAA    $7C0D,Z        ; RX function
         ANDA    #$42
         CMPA    #$40
         BNE     $0136
         LDAB    $7C0F,Z
         RTS
         SUBD    #$0001         ; Delay function
         BNE     $0146
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
         BLS     $01E0
         CLR     $7920,Z
         BCLRW   $0860,Z,#$2000
         JSR     $00,$0202
         LDAB    #$22
         JSR     $00,$0120
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
         JSR     $00,$027C
         RTS
         BCLR    $7C1F,Z,#$80
         BSET    $7C1A,Z,#$80
         CLRA
         DECA
         BEQ     $0298
         BRCLR   $7C1F,Z,#$80,$286
         BCLR    $7C1F,Z,#$80
         TSTA
         BRA     $02A0
         ORP     #$0100
         TPA
         LDAB    #$A5
         RTS
;  do_command45:
         ldab    #$46            ; sequence will be:
                                 ; 0x45 0x07 0xFF 0xBF 0x00 0x40 request
                                 ; 0x46 0x07 0xFF 0xBF 0x00 0x40 response 
                                 ; and should return (in this example) 64 bytes from 0x7FFBF to 0x7FFFF
         jsr     $00,$0120       ; TX 0x46 as 0x45 acknowledge
         jsr     $00,$0136       ; RX
         tbxk                    ; RX Byte0 bank / XK e.g. 0x07
         jsr     $00,$0120       ; echo B0
         jsr     $00,$0136       ; RX Byte1 IX high byte, e.g. 0xFF
         stab    $02FE
         jsr     $00,$0120       ; echo B1
         jsr     $00,$0136       ; RX Byte2 IX low , e.g. 0xBF
         stab    $02FF           
         ldx     $02FE           ; X is now XK:FFBF - we go up from here
         jsr     $00,$0120       ; echo B2 
         jsr     $00,$0136       ; RX Byte3 counter high byte, e.g. 0x00
         stab    $014E
         jsr     $00,$0120       ; echo B3
         jsr     $00,$0136       ; RX Byte4 counter low byte, e.g. 0x40
         stab    $014F
         lde     $014E           ; E is the byte counter
         jsr     $00,$0120       ; echo B4
;  Rd_xmit:
         ldab    0,X
         jsr     $00,$0120       ; Echo byte at address X
         aix     #$01            ; increment the address counter 
         tste    
         lbeq    $0104
         sube    #$01            ; decrement the byte counter
         bra     $02EA           ; if not zero loop
         nop                     ; this is the $02E6 word we pull E from
