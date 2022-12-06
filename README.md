# Experimental SBEC3 reflashing kernel
---------  
I use this script with the embedded reflash kernel and a [CP2102](https://www.amazon.com/gp/product/B07R3388DW) connected to ground, SCI TX (pin 6 in the OBD2 connector) and SCI RX (pin 25 in the 12-pin diag connector next to the OBD2 connector).  +20V programming voltage is supplied by a 24V PoE adapter I had laying around, turned down to 20V with a [buck converter](https://www.amazon.com/dp/B07VVXF7YX) and switched on and off via the CP2102's RTS output and a cheapy mechanical [relay board](https://www.amazon.com/gp/product/B08C71QL65).  For the 2GNT (and probably Avenger, Sebring, Neon, Cloud cars) there is an [annotated excerpt from the FSM](https://github.com/dino2gnt/SBECBootLoader/blob/master/connections.png) illustrating these connections.  I run everything in Linux. It probably won't work under Windows (and I don't care). 

If you connect directly to the ECU on a bench, the pins you need are:

 * Pin 10: Ground
 * Pin 20: Switched 12V+ (Run)
 * Pin 46: Constant 12V+ (Battery)
 * Pin 47: Ground
 * Pin 65: SCI TX
 * Pin 75: SCI RX

In my experience, these connections are universal across the entire SBEC3 family.  If you know of one that is different, please let me know.

12V+ power is supplied by a 12V wall-wart from the box of random power supplies and cables in the back of the closet (you know the box I mean).

For the CP2102:

 * Pin TX connects to Normally Open (NO) on the relay board
 * Pin RX connects to Pin 65 on the ECU (SCI TX)
 * Pin RTS connects to IN on the relay board
 * Pin 5V+ connects to DC+ on the relay board
 * Pin GND to DC- on the relay board
 * Connect the other ground pin to a common ground shared by the ECU power supply
 
On the relay board:

 * Connect 20V+ to Normally Closed (NC)

The ecuwriter script toggles the CP2102's RTS pin in order to switch the 20V+ programming voltage on and off.

## Commands
---------

### Erase:
---------
  * Request: ````20 0X XX XX````
     * 0X XX XX can be any 20 bit address inside the target bank, e.g. Bank 0 is ````04 00 00````
  * Response: ````21 0X XX XX````
     * After the response, we enter a timer-loop that counts down approximately 15 seconds, attempting the block-erase command each iteration until time runs out or it succeeds.  SCI RX must be +20V for the delete to succeed.
    * Success: ````22````
    * Failure: The content of the flash chip's Command State Register containing error bit values

#### Bank base addresses for M28F200 and compatible flash chips:
---------
   * Bank 0: ````0x40000```` (16K)
   * Bank 1: ````0x44000```` (8k)
   * Bank 2: ````0x46000```` (8K)
   * Bank 3: ````0x48000```` (96K)
   * Bank 4: ````0x60000```` (128K)

### Write:
---------

#### Write to buffer:
  * Request: ````30 0Y YY````
    * `YY YY` is the count of bytes to write to RAM buffer, zero indexed, ````0x0000```` to ````0xFFFF````. Writes from Command 30 populate a RAM buffer starting at approximately ````0x00490````. This leaves about 800 bytes of RAM for write buffer on an ECU with 2KB ('96-'97).
    * Response: ````31 YY YY````
       * Follow the response with ````0xYYYY```` bytes of data to be written to RAM buffer
       * Bytes are not echoed
       * SCI RX does NOT have to be +20V
   * Success: ````22```` is echoed when YYYY bytes have been received.
   * **Note**: The RAM buffer size is limited to the amount of available RAM. I don't recommend greater than ````0x0300```` (768 bytes) unless you know what you're doing.  There is no range check and we will happily try to write off the end of RAM and crash if you ask us to.

#### Write to flash:
   * Request: ````40 0X XX XX 0Y YY````
       * 0X XX XX is the starting address in flash memory for the write
       * YYYY is the count of bytes to write from the RAM buffer to flash and should match the YYYY used to stage data to RAM.
   * Response: ````41 0X XX XX YY YY````
      * After sending the response, we enter a timer-loop that counts down approximately 15 seconds, attempting a write each iteration until time runs out or it succeeds. SCI RX must be +20V for the write to succeed.
   * Success: ````22```` is echoed when YY bytes have been successfully written to flash memory
   * Failure:
      * Write error: ````0x01````
      * Timeout: ````0x80````
* **Note**:The expectation is a pattern of ````30 0Y YY <bytes>```` to stage data to RAM, followed by a ````40 0X XX XX 0Y YY```` and a switch to +20V on SCI RX (switched off on 22/success) to write staged data to flash, followed by another 30, then 40, etc, etc.

### Bulk Read:
---------
   * Request: ````45 0X XX XX YY YY````
       * 0X XX XX is a 20 bit address start address for the read
       * YY YY is a 16 bit count of bytes to return
   * Response: ````46 0X XX XX YY YY````
       * Response will be followed by ````YY YY```` count of bytes starting from ````0X XX XX````
   * Success: ````22````
   * **Note**: Too large of a ````YY YY```` value can cause unexpected problems on your receiving device.  Be cautious with large values. 00 40 (64 bytes) is generally safe.

### EEPROM read:
---------
   * Request: ````50 0X XX````
      * 0X XX represents an EEPROM offset.  For example, the ECU part number is offset 0x01F0 to 0x01F2
   * Response: ````51 0X XX YY YY````
      * This command works in full word widths (16 bits) and thus always returns two bytes `YY YY`.
   * Failure:
      * ````51 0X XX 01```` if the EEPROM read fails.

### EEPROM write:
---------
   * Request: ````55 0X XX YY YY````
      * 0X XX represents an EEPROM offset.  
      * YY YY is the 16 bit word to write starting at offset 0X XX
      * SCI RX does _not_ have to be +20V.
   * Response: ````56 0X XX YY YY YY YY````
      * The complete command is echoed with a 56 acknowledge, with the addition of the contents of the EEPROM offset after writing.
      * No error checking is done with these values in the reflash kernel. If they don't match, the write did not succeed. 
   * Failure:
      * ````56 0X XX YY YY 01```` if the EEPROM write fails. (probably?)

# ECUWriter script
---------  
Shows off the basic functions of the reflash kernel. I'm not fluent in Python, so be warned. Requires argparse, signal, time, and pyserial.
```
$ ./ecuwriter.py --help
usage: ecuwriter.py [-h] [--device SERIALDEVICE] [--baud BAUD] [--bootloader BOOTLOADER] [--skip-bootstrap] [--write BINFILE] [--writebuffer BUFFERSIZE] [--read DUMPFILE] [--read-partnum] [--write-partnum] [--read-vin] [--write-vin] [--flash-size {128,256}] [--erase {0,1,2,3,4,ALL}] [--read-serial READSERIAL]
                    [--send-serial SENDSERIAL] [--invert-rts] [--debug]

A basic ECU reader & writer for the SBEC3

options:
  -h, --help            show this help message and exit
  --device SERIALDEVICE, -d SERIALDEVICE
                        The serial device to use (default: /dev/ttyUSB0)
  --baud BAUD, -b BAUD  Connection baud rate (default: 62500)
  --bootloader BOOTLOADER, -l BOOTLOADER
                        Bootloader image to use (default: bootloader.bin)
  --skip-bootstrap, -s  If the ECU is already in bootstrap with a running bootloader, use this to skip handshake and upload (default: False)
  --write BINFILE, -w BINFILE
                        The path and filename of the binary file to write to the ECU
  --writebuffer BUFFERSIZE, -u BUFFERSIZE
                        The amount of ECU RAM to use for write buffer. (default: 2048)
  --read DUMPFILE, -r DUMPFILE
                        Read the ECU flash and store it as DUMPFILE
  --read-partnum, -p    Read and print the part number stored in the ECU EEPROM
  --write-partnum, -n   Write a part number stored to the ECU EEPROM
  --read-vin, -v        Read and print the VIN stored in the ECU EEPROM
  --write-vin, -i       Write a VIN to the ECU EEPROM
  --flash-size {128,256}, -f {128,256}
                        Flash firmware image size. MOST SBEC3 ECUs are 256K (default: 256)
  --erase {0,1,2,3,4,ALL}
                        Erase Flash Bank [0,1,2,3,4|ALL], required prior to reprogramming (default: None)
  --read-serial READSERIAL
                        Read READSERIAL bytes of data from the buffer and exit, used to read the output of raw commands.
  --send-serial SENDSERIAL
                        Write serial data to the device. Used to send raw commands. Follow with --read-serial # to read # bytes of the response
  --invert-rts          Swap RTS hi / low if you are defaulting to RTS hi for some reason (default: False)
  --debug               Show lots of debug output
  ```

# Checksum script
---------  
For writing updated checksums to modified firmware images. Again, not fluent in Python, so Don't Blame Dino™. Requires argparse, signal.
```
$ ./checksum.py --help
usage: checksum.py [-h] --binfile BINFILE [--write-checksum WRITE] [--debug DEBUG]

Calculate and optionally store checksum for an SBEC3 firmware image

optional arguments:
  -h, --help            show this help message and exit
  --binfile BINFILE, -b BINFILE
                        The firmware image to work on
  --write-checksum WRITE, -w WRITE
                        Write the checksum to the firmware image. (default False)
  --debug DEBUG         Show lots of debug output
```
