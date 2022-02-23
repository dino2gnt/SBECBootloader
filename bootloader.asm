         ORG     $0100
         LBRA    $01B8
         JSR     $00,$019E
         CMPB    #$10
         BEQ     $0118
         CMPB    #$20
         BEQ     $0172
         CMPB    #$30
         JSR     $030A
         BNE     $0104
         LDAB    #$11
         JSR     $00,$0188
         JSR     $00,$019E
         STAB    $01B6
         LDAB    $01B6
         JSR     $00,$0188
         JSR     $00,$019E
         STAB    $01B7
         LDAB    $01B7
         JSR     $00,$0188
         LDAB    #$00
         TBXK
         LDX     #$0206
         JSR     $00,$019E
         STAB    $00,X
         LDAB    $00,X
         JSR     $00,$0188
         AIX     #$01
         DECW    $01B6
         BNE     $0146
         LDD     #$0FA0
         JSR     $00,$01AE
         LDAB    #$04
         TBXK
         LDX     #$8000
         LDAB    #$14
         JSR     $00,$0188
         BRA     $0104
         LDAB    #$21
         JSR     $00,$0188
         JSR     $00,$0206
         BRA     $0104
         JSR     $00,$019E
         JSR     $00,$0188
         RTS
         LDAA    $7C0C,Z
         ANDA    #$01
         BEQ     $0188
         STAB    $7C0F,Z
         LDD     #$0320
         JSR     $00,$01AE
         RTS
         LDAA    $7C0D,Z
         ANDA    #$42
         CMPA    #$40
         BNE     $019E
         LDAB    $7C0F,Z
         RTS
         SUBD    #$0001
         BNE     $01AE
         RTS
         NOP
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
         BLS     $0248
         CLR     $7920,Z
         BCLRW   $0860,Z,#$2000
         JSR     $00,$026A
         LDAB    #$22
         JSR     $00,$0188
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
         JSR     $00,$02E4
         RTS
         BCLR    $7C1F,Z,#$80
         BSET    $7C1A,Z,#$80
         CLRA
         DECA
         BEQ     $0300
         BRCLR   $7C1F,Z,#$80,$2EE
         BCLR    $7C1F,Z,#$80
         TSTA
         BRA     $0308
         ORP     #$0100
         TPA
         LDAB    #$A5
         RTS
         LDAB    #4
         TBXK
         LDX     #0
         LDAB    0,X
         JSR     $00,$0188
         AIX     #1
         TXKB
         CMPB    #8
         BNE     $0312
         RTS
