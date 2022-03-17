         ORG     $0100
         LBRA    SETUP          ; initialization is at the very end, so it can be run once and overwritten
START:   JSR     RXBYTE
         CMPB    #$10           ; cmd 10 doesn't have a use yet
         BEQ     START
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
         ldx     ADRWORD         ; 0x40000 bank 0
                                 ; 0x44000 bank 1
                                 ; 0x46000 bank 2
                                 ; 0x48000 bank 3
                                 ; 0x60000 bank 4
ERLOOP:  jsr     INITGPT         ; init GPT
         jsr     TIMEOUT         ; set timeout
         ldd     #$1F            ; set retries
         std     CNTBYTE         ; store retries

TMRLOOP: brclr   $7922,Z,#$10,TMRGOOD
         jsr     TIMEOUT         ; Reset timeout until retries=0
         jsr     CLRSTAT
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
         jsr     RDCOUNT         ; broke this out into a sub to reduce size
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

RDCOUNT: jsr     RXBYTE          ; tell us how many bytes you're sending
         stab    CNTBYTE         ; size high bye
         jsr     TXBYTE
         jsr     RXBYTE          ; get low byte
         stab    CNTBYTE+1
         jsr     TXBYTE
         incw    CNTBYTE         ; because I am a terrible coder.
         rts

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
         jsr     CLRSTAT
         decw    ADRWORD         ; 256 divider should be slightly less than a second per retry?
         beq     TMOUTERR        ; Timeout error

WTMRGOOD: jsr     RD_STAT         ; Fetch status
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
         ldab    #$22            ; 22 seems to generally be "success"
         bra     ECHOXIT

EFFS:    jsr     RDARRAY 
         ldd     E,X             ; Read word from flash @ X+count
         subd    E,Y             ; Subtract Memory Effs from Flash Effs
         bne     WR_ERR          ; If one of those wasn't 0xFFFF, we fucked up.
         ldd     E,X             ; Read the word at X+count from flash (again)
         jsr     TXFLSHWD        ; Echo the two bytes of 0xFF we didn't write
         bra     WRINCLP         ; go back into the loop and increment

WR_ERR:  jsr     RDARRAY
         ldab    #1              ; load B with value (error writing flash)
         bra     ECHOXIT

TMOUTERR: ldab    #$80            ; i guess.
ECHOXIT: jsr     TXBYTE
         lbra    START           ; no dice homey

RDARRAY: ldd     #0FFh           ; CSM Read Array command
         std     E,X             ; Send CSM Read Array
         rts
         
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
         tbyk                    ; YK:IY = 0x00396
         ldy      #SETUP          ; NOTE this is the memory location for the start of SETUP and will change
         rts                     ; if the assembly changes. We overwrite our init code as RAM buffer. I couldn't figure 
                                 ; how to do this with a label :(
TXFLSHWD: stab    RDR_X          ; store B to word
         tab                     ; A -> B
         jsr     TXBYTE          ; Echo B
         ldab    RDR_X           ; load B with memory content
         jsr     TXBYTE          ; write SCI byte from B
         rts 

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
