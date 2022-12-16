; bootloader-reflash.asm
;
; SBECBootloader (https://github.com/dino2gnt/SBECBootloader)
; Copyright (C) 2022, Dino Yancey
;
; MCU: 68HC16Z
; For 128KB Flash chip TI TMS28F210 or compatible
;
; A feature-rich monolithic kernel for interacting with
; 60HC16Z based Chrysler SBEC3 engine management units.
;
         ORG     $0100
         LBRA    SETUP          ; initialization is at the very end, so it can be run once and overwritten
START:   jsr     RXBYTE
         cmpb    #$10           ; cmd 10 will echo 11 (are you alive?)
         beq     CMD_10
         cmpb    #$20           ; cmd 20 is bank erase
         lbeq    CMD_20
         cmpb    #$30           ; cmd 30 is write flash chunk to mem
         lbeq    CMD_30
         cmpb    #$40           ; cmd 40 is read from mem and write to flash
         lbeq    CMD_40
         cmpb    #$45           ; cmd 45 is bulk memory dump
         lbeq    CMD_45
         cmpb    #$50           ; cmd 50 is read word from EEPROM offset
         lbeq    CMD_50
         cmpb    #$55           ; cmd 55 is write word to EEPROM offset
         lbeq    CMD_55
         bne     START

CMD_10:  ldab    #$11
         jsr     TXBYTE
         beq     START

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
         tbxk                    ; B -> XK
         jsr     TXBYTE 
         jsr     RXBYTE          ; read address high byte
         stab    ADRWORD         
         jsr     TXBYTE
         jsr     RXBYTE          ; read address low byte
         stab    ADRWORD+1       ; XK:IX is the address in the flash bank to erase  
         jsr     TXBYTE
         ldx     ADRWORD         ; 0x40000 bank 0 128KB data from 0x40000 0x5FFFF

ERLOOP:  jsr     INITGPT         ; init GPT
         jsr     TIMEOUT         ; set timeout
         ldd     #$FF            ; set retries
         std     CNTBYTE         ; store retries

TMRLOOP: brclr   $7922,Z,#$10,TMRGOOD
         jsr     TIMEOUT         ; Reset timeout until retries=0
         decw    CNTBYTE         ; 256 divider with 15 retries should be over 10 clock seconds?
         beq     ER_TMOUT

; the main erase loop
TMRGOOD: 
         ldd     #$0040          ; 0x40 word write setup
         std     0,X             ; send command
         clrd                    ; payload is zero
         std     0,X             ; First we program everything to 0x0000
         ldd     #$0010          ; sit for some cycles
         jsr     Delay
         ldd     #$00C0          ; 0xC0 verify write
         std     0,X             ; send command
         ldd     #$000A          ; delay
         jsr     Delay
         ldd     0,X             ; Read the word at X
         bne     TMRLOOP         ; if we didn't zero it, keep retrying
         aix     #2
         txkb                    ; copy XK to rB
         cmpb    #6              ; if XK is 6 we're done
         bcs     ERLOOP          ; If we made it here and X is less than 0x60000, reset the timers and loop
         ldx     ADRWORD         ; reset X

ERASE:   ldd     #$0020          ; flash erase command
         std     0,X             ; word address
         ldd     #$0020          ; erase confirm
         std     0,X
         ldd     #$4000          ; 16K cycles ~10.25mS
         jsr     DELAY
V_LOOP:
         ldd     #$00A0          ; Verify cmd
         std     0,X             ; Send cmd  
         ldd     #$0A            ; 16K cycles ~10.25mS
         jsr     DELAY
         ldd     0,X             ; read  the word at X
         cpd     #$FFFF          ; should be FFFF
         bne     ERASE           ; if it's not FFFF then we need to erase it again
         aix     #2              ; move to next word
         txkb                    ; copy XK to rB
         cmpb    #6              ; if XK is 6 we're done
         bne     V_LOOP
         aix     #-2             ; put us back on the last word or the flash
         clrd
         std     0,X             ; send read mode to command register
         ldab    #$22            ; no errors, we're good?
         bra     TX_RTN

ER_TMOUT:
         ldab   #$80
TX_RTN:  jsr     TXBYTE          ; B will contain error or success
         clrd                    ; put the flash chip back in read mode
         std     0,X
         lbra    START           ; if no match, bail out

         rts


; Set timeout
TIMEOUT: ldd     $790A,Z         ; Timer Counter Register (TCNT)
         addd    #$0F424
         std     $7916,Z         ; Timer Output Compare Register 2 (TOC2)
         bclr    $7922,Z,#$10    ; clear PAIF on TFLG1
         rts
; Init GPT
INITGPT: clr     $791E,Z         ; Timer Control Register 1 (TCTL1)
         ldab    #6              ; 256 divider
         stab    $7921,Z         ; Timer Mask Register 2 (TMSK2)
         rts
CMD_30:  ldab    #$31            ; request 0x30, 0xFF: upload 255 bytes
         jsr     TXBYTE          ; Send 0x31 acknowledge
         jsr     RDCOUNT         ; broke this out into a sub to reduce size
         jsr     LOADY
         clre                    ; Clear E
RD_STOR: jsr     RXBYTE          ; Read a byte
         stab    E,Y             ; Store it starting at E = 0 and Y = #START
         adde    #1
         cpe     CNTBYTE         ; if E - CNTBYTE == 0
         bne     RD_STOR         ; Not there yet, keep reading
         clre                    ; Clear E
         ldab    #$22
         jsr     TXBYTE          ; Everything's cool
         lbra    START
CNTBYTE: NOP                     ; count of bytes in buffer

RDCOUNT: jsr     RXBYTE          ; tell us how many bytes you're sending
         stab    CNTBYTE         ; size high bye
         jsr     TXBYTE
         jsr     RXBYTE          ; get low byte
         stab    CNTBYTE+1
         jsr     TXBYTE
         rts

CMD_40:  ldab    #$41
         jsr     TXBYTE          ; Send 0x41 acknowledge
         jsr     PGMADDR         ; get the byte count and starting address for write
         jsr     LOADY

WR_LOOP: jsr     INITGPT         ; init GPT
         jsr     TIMEOUT         ; set timeout
         ldd     #$FF            ; retries
         std     ADRWORD         ; store retries
WTMRLOOP: 
         brclr   $7922,Z,#$10,WTMRGOOD
         jsr     TIMEOUT         ; Reset timeout until retries=0
         decw    ADRWORD         ; 256 divider should be slightly less than a second per retry?
         beq     TMOUTERR        ; Timeout error

WTMRGOOD: 
         ldd     E,Y             ; payload from RAM
         cpd     #$FFFF          ; Flash program can only write zeros; an erased flash is all ones (0xFFFF)
         beq     WR_INC_LOOP     ; if it's all 0xFFFF, we don't write it, just increment and loop
         ldd     #$40            ; 0x40 word write setup
         std     E,X             ; send command
         ldd     E,Y             ; payload from RAM
         std     E,X             ; write payload
         ldd     #$000F          ; sit 16 cycles
         jsr     Delay
         ldd     #$00C0          ; 0xC0 verify write
         std     E,X             ; send command
         ldd     #$000B          ; sit
         jsr     Delay
         clrd                    ; Zero D
         std     E,X             ; put the flash chip back in read mode
         ldd     E,X             ; Read the word at X
         subd    E,Y             ; Compare it to the word in RAM
         bne     WTMRLOOP        ; Write failed, retry

WR_INC_LOOP: 
         adde    #2              ; We're good, move to the next word
         cpe     CNTBYTE         ; if E - $count == 0
         bne     WR_LOOP         ; if it's not zero we still have more to go
         ldab    #$22            ; 22 seems to generally be "success"
         lbra    TX_RTN

WR_ERR:  ldab    #1              ; load B with value (error writing flash)
         lbra    TX_RTN

TMOUTERR:
         ldab    #$80            ; i guess.
         lbra    TX_RTN

PGMADDR: jsr     RXBYTE          ; Read BANK byte
         tbxk                    ; XK is now Byte
         jsr     TXBYTE          ; Echo the byte back
         jsr     RXBYTE          ; read a new byte
         stab    ADRWORD         ; Store byte to RAM
         jsr     TXBYTE          ; echo it
         jsr     RXBYTE          ; read the next byte
         stab    ADRWORD+1       ; Store it to RAM
         jsr     TXBYTE          ; echo it
         jsr     RDCOUNT         ;  broke this out into a sub to reduce size
         ldx     ADRWORD         ; XK = Byte0
                                 ; X = Byte1 : Byte2
         clre                    ; E = 0x0
         rts

LOADY:   ldab    #0
         tbyk                    ; YK:IY = 0x00XXX
         ldy     #SETUP          ; Use the memory location for the start of SETUP so we overwrite it
         rts                     

; CMD 50 / 55 read & write EEPROM 
CMD_50:  ldab    #$51
         jsr     TXBYTE          ; echo 51 
         jsr     RDCOUNT         ; reuse RDCOUNT to save space
         bra     RDEEPROM

CMD_55:  ldab    #$56
         jsr     TXBYTE          ; echo 56
         jsr     RDCOUNT         ; reuse RDCOUNT to save space, buts H&L byte in CNTBYTE
         jsr     RXBYTE          ; eeprom offset high byte
         stab    ADRWORD         ; payload
         jsr     TXBYTE          ; echo B1
         jsr     RXBYTE          ; eeprom offset low byte
         stab    ADRWORD+1       ; payload
         jsr     TXBYTE          ; echo B2
         bra     WREEPROM

QSPIBUSY:bclr    $7C1F,Z,#80h    ; Clear QSPI finished flag
         bset    $7C1A,Z,#80h    ; set DTL
         clra
QSPI_BL: deca
         beq     QSPIBAIL
         brclr   $7C1F,Z,#80h,QSPI_BL ; Loop until QSPI finished flag is set
         bclr    $7C1F,Z,#80h    ; Clear QSPI finished flag
QSPIBAIL: tsta
         rts

RDEEPROM:ldd     CNTBYTE
         cpd     #$200
         bcc     QSPIERR
         asla
         asla
         asla
         oraa    #3
         std     $7D22,Z         ; txram
         ldaa    #$CB
         ldab    #$4B
         std     $7D41,Z         ; cmd ram
         ldd     #$201
         std     $7C1C,Z         ; SPCR2
         jsr     QSPIBUSY
         beq     QSPIERR 
         ldd     $7D04,Z         ; rxram
         tde
         tab
         jsr     TXBYTE          ; echo rA
         ted
         jsr     TXBYTE          ; echo rB
         lbra    START
QSPIERR: ldab    #$1             ; Error
         jsr     TXBYTE
         lbra    START

WREEPROM: 
         ldaa    #$0B
         staa    $7D41,Z         ; cmdram
         ldd     #6
         std     $7D22,Z         ; txram
         ldd     #$101
         std     $7C1C,Z         ; spcr2
         jsr     QSPIBUSY
         beq     QSPIERR
         ldd     CNTBYTE         ; eeprom offset
         cpd     #$200
         bcc     QSPIERR
         asla
         asla
         asla
         oraa    #2 
         std     $7D22,Z         ; txram
         ldd     ADRWORD         ; payload in ADRWORD
         std     $7D24,Z         ; txram this was 24
         ldaa    #$0B
         staa    $7D43,Z         ; cmdram
         ldaa    #$CB 
         ldab    #$4B 
         std     $7D41,Z         ; cmdram this was 41
         ldd     #$201
         std     $7C1C,Z         ; spcr2
         jsr     QSPIBUSY
         beq     QSPIERR
         ldd     #5000
         jsr     DELAY
         lbra    RDEEPROM

; SETUP SECTION - everything past this point is overwritten by CMD30 payload
SETUP:   ORP     #$00E0         
         LDAB    #$0F
         TBZK
         LDZ     #$8000          ; ZK:IZ = 0xF8000
         LDAB    #$00
         TBSK                    ; SK = 0x00 
         LDS     #$07F6          ; set the stack pointer near 2KB 0x007F6
         ldab    $7A02,Z         ; SIMTR register
         cmpb    #$83            ; Z2 MCU with 2K RAM?
         beq     SKIPLDS         ; If SIMTR == 83, we're limited to 2KB
         LDS     #$0FF6          ; If not, set the stack pointer near 4KB 0x00FF6
SKIPLDS: CLRB
         TBEK                    ; EK = 0x00
         TBYK                    ; YK = 0x00
         LDD     #$0148          ; I had really good notes written on all the Chip Select register values
         STD     $7A00,Z         ; being assigned here to bring up the flash on 0x40000
         BCLR    $7A21,Z,#$80    ; but lost them in an IDA crash ;-/
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
         LDAB    #$22           ; Init succeeded 
         JSR     TXBYTE
         LBRA    START
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
START_SPI: BCLR  $7C1F,Z,#$80
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
SPI_RTN: RTS
