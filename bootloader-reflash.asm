         ORG     $0100
         LBRA    SETUP
START:   JSR     RXBYTE
         CMPB    #$10           ; cmd 10 doesn't have a use yet
         lBEQ    START
         CMPB    #$20           ; cmd 20 is bank erase
         LBEQ    CMD_20
         CMPB    #$30           ; 30 is write flash chunk to mem
         lBEQ    CMD_30
         CMPB    #$40           ; 40 is copy from mem to flash
         lBEQ    CMD_40
         CMPB    #$45           ; bulk memory dump
         lBEQ    CMD_45
         BNE     START
TXBYTE:  LDAA    $7C0C,Z        ; TX function
         ANDA    #$01
         BEQ     TXBYTE
         STAB    $7C0F,Z
         LDD     #$0043         ; this is the TX delay interval
         JSR     DELAY
         RTS
RXBYTE:  LDAA    $7C0D,Z        ; RX function
         ANDA    #$42
         CMPA    #$40
         BNE     RXBYTE
         LDAB    $7C0F,Z
         RTS
DELAY:   SUBD    #$0001         ; Delay function
         BNE     DELAY
         RTS
RDR_X:   NOP                    ; Reader X byte
SETUP:   ORP     #$00E0
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
LOOP1:   ADDE    #$04
         CPE     #$0838
         BLS     LOOP1
         CLR     $7920,Z
         BCLRW   $0860,Z,#$2000
         JSR     QSPI
         LDAB    #$22
         JSR     TXBYTE
         JMP     START
QSPI:    LDD     #$4088
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
         JSR     START_SPI
         RTS
START_SPI: BCLR    $7C1F,Z,#$80
         BSET    $7C1A,Z,#$80
         CLRA
BUSYLOOP: DECA
         BEQ     SET_V
         BRCLR   $7C1F,Z,#$80,BUSYLOOP
         BCLR    $7C1F,Z,#$80
         TSTA
         BRA     SPI_RTN
SET_V:   ORP     #$0100
         TPA
         LDAB    #$A5
SPI_RTN: RTS
;  Command 45 / Memory dump:
CMD_45:  ldab    #$46            ; sequence will be:
                                 ; 0x45 0x07 0xFF 0xBF 0x00 0x40 request
                                 ; 0x46 0x07 0xFF 0xBF 0x00 0x40 response 
                                 ; and should return (in this example) 64 bytes from 0x7FFBF to 0x7FFFF
         jsr     TXBYTE          ; TX 0x46 as 0x45 acknowledge
         jsr     RXBYTE          ; RX
         tbxk                    ; RX Byte0 bank / XK e.g. 0x07
         jsr     TXBYTE          ; echo B0
         jsr     RXBYTE          ; RX Byte1 IX high byte, e.g. 0xFF
         stab    ADRWORD
         jsr     TXBYTE          ; echo B1
         jsr     RXBYTE          ; RX Byte2 IX low , e.g. 0xBF
         stab    ADRWORD+1     
         ldx     ADRWORD         ; X is now XK:FFBF - we go up from here
         jsr     TXBYTE          ; echo B2 
         jsr     RXBYTE          ; RX Byte3 counter high byte, e.g. 0x00
         stab    RDR_X
         jsr     TXBYTE          ; echo B3
         jsr     RXBYTE          ; RX Byte4 counter low byte, e.g. 0x40
         stab    RDR_X+1
         jsr     TXBYTE          ; echo B4
RDRLOOP: ldab    0,X
         jsr     TXBYTE          ; Echo byte at address X
         aix     #$01            ; increment the address counter 
         decw    RDR_X
         bne     RDRLOOP
         lbra    START
ADRWORD: NOP                     ; this is the memory word we pull E from

CMD_20:  ldab    #$21            ; echo 21 for 20 acknowledge
         jsr     TXBYTE
         jsr     RXBYTE          ; read memorybank for xk
         tba
         tbxk                    ; this is stupid
         tab
         jsr     TXBYTE          ; RX -> b -> A, b -> xk, a -> b, echo B.
         jsr     TXBYTE
         jsr     RXBYTE          ; read address high byte
         stab    ADRWORD         
         jsr     TXBYTE
         jsr     RXBYTE          ; read address low byte
         stab    ADRWORD+1       ; XK:IX is the address in the flash bank to erase  
         jsr     TXBYTE
         ldx     ADRWORD         ; 0x40000 bank 0
                                 ; 0x44000 bank 1
                                 ; 0x46000 bank 2
                                 ; 0x48000 bank 3
                                 ; 0x60000 bank 4
ERLOOP:  jsr     INITGPT         ; init GPT
         jsr     TIMEOUT         ; set timeout
         ldd     #$1F            ; set retries
         std     CNTBYTE         ; store retries
         jsr     CLRSTAT

TMRLOOP: brclr   $7922,Z,#$10,TMRGOOD
         jsr     TIMEOUT         ; Reset timeout until retries=0
         decw    CNTBYTE         ; 256 divider with 15 retries should be over 10 clock seconds?
         beq     ER_TMOUT

TMRGOOD: jsr     ERASE           ; if WSM is ready, send erase commands
         jsr     RD_STAT         ; Fetch status
         andd    #$80            ; check ready bit
         beq     TMRLOOP         ; bit 8 = 0, busy / not ready
         jsr     RD_STAT         ; Fetch status
         andd    #$78            ; Erase suspended / Vpp range error &tc
         bne     TMRLOOP         ; Erase failed, retry
         ldab    #$22            ; no errors, we're good?
         bra     TX_RTN

ER_TMOUT: jsr     RD_STAT        ; return failure status code
TX_RTN:  jsr     TXBYTE          ; B will contain error or success
         jsr     CLRSTAT         ; put us back in read-array
         lbra    START           ; if no match, bail out

RD_STAT: ldd     #$70            ; CMD Read Status Register
         std     0,X
         ldd     0,X             ; Read Status register
         rts                     ; Status register in D

CLRSTAT: ldd     #$50
         std     0,X             ; Clear CSM status register
         rts

ERASE:   ldd     #$20            ; CMD erase
         std     0,X             ; Bank address
         ldd     #$D0            ; CMD erase confirm
         std     0,X
         rts

; Set timeout
TIMEOUT: ldd     $790A,Z         ; Timer Counter Register (TCNT)
         addd    #$0F424
         std     $7916,Z         ; Timer Output Compare Register 2 (TOC2)
         ldab    $7922,Z         ; Timer Flag Register 1 (TFLG1)
         bclr    $7922,Z,#$10
         rts
; Init GPT
INITGPT: clr     $791E,Z         ; Timer Control Register 1 (TCTL1)
         ldab    #6              ; 256 divider
         stab    $7921,Z         ; Timer Mask Register 2 (TMSK2)
         rts
CMD_30:  ldab    #$31            ; request 0x30, 0xFF: upload 255 bytes
         jsr     TXBYTE          ; Send 0x31 acknowledge
         jsr     RXBYTE          ; tell us how many bytes you're sending
         clra                    ; clear A
         std     CNTBYTE         ; D = A:B, A = 00000000, store low byte B in RAM
         incw    CNTBYTE         ; because I am a terrible coder.
         jsr     TXBYTE          ; echo size byte 
         jsr     LOADY
         clre                    ; Clear E
RD_STOR: jsr     RXBYTE          ; Read a byte
         stab    E,Y             ; Store it starting at E = 0 and Y = 0x00680
         adde    #1
         decw    CNTBYTE         
         bne     RD_STOR         ; Not there yet, keep reading
         clre                    ; Clear E
         ldab    #$22
         jsr     TXBYTE          ; Everything's cool
         lbra    START
CNTBYTE: NOP                     ; count of bytes in buffer

CMD_40:  ldab    #$41
         jsr     TXBYTE          ; Send 0x41 acknowledge
         jsr     PGMADDR         ; get the byte count and starting address for write
         jsr     LOADY
         jsr     CLRSTAT

WR_LOOP: jsr     INITGPT         ; init GPT
         jsr     TIMEOUT         ; set timeout
         ldd     #$1F            ; set a lot of retries cuz i'm slow.
         std     ADRWORD         ; store retries
WTMRLOOP: brclr   $7922,Z,#$10,WTMRGOOD
         jsr     TIMEOUT         ; Reset timeout until retries=0
         decw    ADRWORD         ; 256 divider should be slightly less than a second per retry?
         beq     TMOUTERR        ; Timeout error
;         jsr     RD_STAT
;         jsr     TXBYTE
WTMRGOOD: jsr    CLRSTAT
         jsr     RD_STAT         ; Fetch status
         andd    #$80            ; check ready bit
         beq     WTMRLOOP        ; bit 8 = 0, busy / not ready
         ldd     E,Y             ; Read a memory word stored by command 30
         cpd     #0FFFFh         ; There's an assumption that we only write to an erased flash, which is all 0xFFFF
         beq     EFFS            ; if it's all 0xFFFF, we don't write it
         ldd     #$40            ; CSM 0x40 program setup command
         std     E,X             ; Send program setup command
         ldd     E,Y             ; load D with saved flash word at Y + value
         std     E,X             ; Write word from Y+count to flash memory at X+count
         jsr     RD_STAT         ; Fetch status
         andd    #$78            ; vpp low & program word errors
         bne     WTMRLOOP        ; Write failed, retry
WRINCLP: adde    #2              ; We're good, move to the next word
         cpe     CNTBYTE         ; if E - $count == 0
         bne     WR_LOOP         ; if it's not zero we still have more to go
         ldab    #22h            ; 22 seems to generally be "success"
         jsr     TXBYTE
         lbra    START
EFFS:    ldd     #0FFh           ; CSM Read Array command
         std     E,X             ; Send CSM Read Array
         ldd     E,X             ; Read word from flash @ X+count
         subd    E,Y             ; Subtract Memory Effs from Flash Effs
         bne     WR_ERR          ; If one of those wasn't 0xFFFF, we fucked up.
         ldd     E,X             ; Read the word at X+count from flash (again)
         jsr     TXFLSHWD        ; Echo the two bytes of 0xFF we didn't write
         bra     WRINCLP         ; go back into the loop and increment

WR_ERR:  ldd     #0FFFFh         ; load D with value (problematic areas are overwritten with FF)
         std     E,X             ; store D to flash memory at X + value
         ldab    #1              ; load B with value (error writing flash)
         jsr     TXBYTE          ; send it
         lbra    START           ; thank you drive through
TMOUTERR: ldab    #$80            ; i guess.
         jsr     TXBYTE
         lbra    START           ; no dice homey
         
PGMADDR: jsr     RXBYTE          ; Read BANK byte
         tbxk                    ; XK is now Byte
         jsr     TXBYTE          ; Echo the byte back
         jsr     RXBYTE          ; read a new byte
         stab    ADRWORD         ; Store byte to RAM
         jsr     TXBYTE          ; echo it
         jsr     RXBYTE          ; read the next byte
         stab    ADRWORD+1       ; Store it to RAM
         jsr     TXBYTE          ; echo it
         jsr     RXBYTE          ; read another byte
         clra                    ; clear A
         std     CNTBYTE         ; D = A:B, A = 00000000, store low byte B in RAM
         jsr     TXBYTE          ; echo it
         incw    CNTBYTE         ; Because i'm a hack
         ldx     ADRWORD         ; XK = Byte0
                                 ; X = Byte1 : Byte2
         clre                    ; E = 0x0
         rts

LOADY:   ldab    #0
         tbyk    
         ldy     #680h           ; YK:IY = 0x00680 RAM Buffer addr CHANGE ME
         RTS

TXFLSHWD: stab    RDR_X          ; store B to word
         tab                     ; A -> B
         jsr     TXBYTE          ; Echo B
         ldd     #140h           ; 320 count of delay
         jsr     DELAY            
         ldab    RDR_X           ; load B with memory content
         jsr     TXBYTE          ; write SCI byte from B
         rts 