         ORG     $0100
         LBRA    SETUP
START:   JSR     RXBYTE
         CMPB    #$10           ; cmd 10 doesn't have a use yet
         lBEQ    START
         CMPB    #$20           ; cmd 20 is bank erase
         LBEQ    CMD20
         CMPB    #$30
         lBEQ    START
         CMPB    #$40
         lBEQ    START
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

CMD20:   ldab    #$21            ; echo 21 for 20 acknowledge
         jsr     TXBYTE
         jsr     RXBYTE          ; read bank 0x00 - 0x04
         jsr     TXBYTE          ; echo bank
         ldab    #$4
         tbxk
         ldx     #$0             ; 0x40000
         ldab    #$50
         jsr     INITGPT         ; init GPT
         jsr     CSM_RDY         ; check ready
         CMPB    #$00
         beq     BANK0
         CMPB    #$01
         beq     BANK1
         CMPB    #$02
         beq     BANK2
         CMPB    #$03
         beq     BANK3
         CMPB    #$04
         beq     BANK4

TX_RTN:  jsr     TXBYTE          ; B will contain error or success
         LBRA    START
                                 ; XK:IX = 0x40000
BANK0:   bra     ERASE           ; jump erase flash

BANK1:   ldx     #$4000          ; XK:IX = 0x44000
         bra     ERASE           ; jump erase flash

BANK2:   ldx     #$6000          ; XK:IX = 0x46000
         bra     ERASE           ; jump erase flash

BANK3:   ldx     #$8000          ; XK:IX = 0x48000
         bra     ERASE           ; jump erase flash

BANK4:   ldab    #$6
         tbxk
         ldx     #$0000          ; XK:IX = 0x60000
         bra     ERASE           ; jump erase flash

ERASE:   ldd     #$20            ; CMD  Erase
         std     0,X             ; Block Address
         ldd     #$0D0           ; CMD Erase Resume/Erase Confirm
         std     0,X
         ldab    #$22            ; success
         BRA     TX_RTN
; Set timeout
TIMEOUT: ldd     $790A,Z         ; Timer Counter Register (TCNT)
         addd    #$0F424
         std     $7916,Z         ; Timer Output Compare Register 2 (TOC2)
         ldab    $7922,Z         ; Timer Flag Register 1 (TFLG1)
         bclr    $7922,Z,#$10
         rts
; Init GPT
INITGPT: clr     $791E,Z         ; Timer Control Register 1 (TCTL1)
         ldab    #$6             ; 256 divider
         stab    $7921,Z         ; Timer Mask Register 2 (TMSK2)
         rts
; Check flash CSM ready
CSM_RDY: jsr     TIMEOUT         ; set timeout
         ldab    #$0A            ; 10 attempts with 256 divider ~ 10 seconds
         stab    ADRWORD
  ; not ready         
NOTRDY:  brclr   $7922,Z,#$10,CHKRDY ; Check Flag Timeout
         jsr     TIMEOUT         ; Set tmeout - new attempt
         decw    ADRWORD
         bne     CHKRDY
         ldab    #$80            ; return error "not ready"
         bra     BAIL            ; set error abd bail 
  ; check ready       
CHKRDY:  ldd     #$70            ; CMD Read Status Register
         std     0,X
         ldd     0,X             ; Read Status registr
         andd    #$80            ; check Flag Ready
         beq     NOTRDY          ; no,repeat check flag
         ldd     0,X             ; else
         andd    #$78            ; Check for other errors in the status register.
BAIL:    rts

CMD_30:  ldab    #31h
         jsr     TXBYTE          ; Send 0x31 acknowledge
         jsr     RXBYTE          ; tell us how many bytes you're sending
         clra                    ; clear A
         std     CNTBYTE         ; D = A:B, A = 00000000, store low byte B in RAM
         jsr     TXBYTE          ; echo size byte 
         jsr     LOADY
         clre                    ; Clear E
RD_STOR: jsr     RXBYTE
         stab    E,Y             ; This should be E = 0 and Y = 0x00680
         adde    #1
         cpe     CNTBYTE         ; Counting up to a known size
         bcs     RD_STOR         ; Not there yet, keep reading
         ldd     #4000           ; 4000 count delay
         jsr     Delay
         clre                    ; Clear E
CNTBYTE: NOP

CMD_40:  ldab    #41h
         jsr     TXBYTE          ; Send 0x41 acknowledge
         jsr     PGMADDR         ; get the byte count and starting address for write
         jsr     LOADY
         ldd     #50h            ; clear CSM status register command
         std     E,X             ; clear CSM status register
WRITE:   ldd     E,Y             ; load D with word from RAM @ Y + count index
         cpd     #0FFFFh         ; If it's 0xFFFF...
         beq     EFFS            ; Skip it. Blank flash word is 0xFFFF
         ldd     #40h            ; CSM 0x40 program setup command
         std     E,X             ; Send program setup command
         ldd     E,Y             ; load D with saved flash word at Y + value
         std     E,X             ; Write word from Y+count to flash memory at X+count
CHKCSM:  ldd     #70h            ; read status register cmd
         std     E,X             ; Send Read Status Register command
         ldd     E,X             ; Read the CSM status register
         andd    #80h            ; check CSM ready bit
         beq     CHKCSM          ; loop if its not ready (0=busy)
         ldd     E,X             ; read the CSM status register again
         andd    #78h            ; Vpp Status, Program Error, Erase Error, Erase-suspend status bits
         bne     WR_ERR          ; Error flag(s) set, bail

EFFS:    ldd     #0FFh           ; CSM Read Array command
         std     E,X             ; Send CSM Read Array 
         ldd     E,X             ; Read word from flash @ X+count
         subd    E,Y             ; Subtract Memory Effs from Flash Effs
         bne     WR_ERR          ; If one of those wasn't 0xFFFF, we fucked up.
         ldd     E,X             ; Read the word at X+count from flash (again)
         jsr     TXFLSHWD        ; Echo the two bytes of 0xFF we didn't write
         adde    #2              ; Inc count by 2 (cuz words)
         cpe     CNTBYTE         ; compare E to block size
         blt     WRITE           ; branch if less than zero
         ldab    #22h            ; 22 seems to generally be "success"
         jsr     TXBYTE
         lbra    START           ; branch always to read another command

WR_ERR:  ldd     #0FFFFh         ; load D with value (problematic areas are overwritten with FF)
         std     E,X             ; store D to flash memory at X + value
         ldab    #1              ; load B with value (error writing flash)
         jsr     TXBYTE          ; send it
         lbra    START           ; thank you drive through
         
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
         ldx     ADRWORD         ; XK = Byte0
                                 ; X = Byte1 : Byte2
         lde     #0AA55h         ; E = 0x0AA55
         rts

LOADY:   ldab    #0
         tbyk    
         ldy     #680h           ; YK:IY = 0x00680 RAM Buffer addr CHANGE ME
         RTS

TXFLSHWD: stab    RDR_X          ; store B to B
         tab                     ; A -> B
         jsr     TXBYTE          ; Echo B
         ldd     #140h           ; 320 count of delay
         jsr     DELAY            
         ldab    RDR_X           ; load B with memory content
         jsr     TXBYTE          ; write SCI byte from B
         rts 
