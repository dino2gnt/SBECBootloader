# Experimental SBEC3 reflashing kernel
---------  

## Commands
---------

### Erase:
---------
  * Request: ````20 0X XX XX````
     * 0X XX XX can be any 20 bit address inside the target bank, e.g. Bank 0 is ````04 00 00````
  * Response: ````21 0X XX XX````
     * After the response, we enter a timer-loop that counts down approximately 15 seconds, attempting the delete command each iteration until time runs out or it succeeds.  SCI RX must be +20V for the delete to succeed.
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
  * Request: ````30 YY````
         * YY is the count of bytes to write to RAM buffer, zero indexed, ````0x00```` to ````0xFF````. Writes initially populate a RAM buffer of max 256 bytes starting at ````0x00680````
    * Response: ````31 YY````
       * Follow the response with XX bytes of data to be written to RAM buffer
       * Bytes not echoed
       * SCI RX does NOT have to be +20V
   * Success: ````22```` is echoed when XX bytes have been received
   * **Note**: The RAM buffer size is limited to 255 bytes because it is read from an 8 bit value. This may be revised / increased later, there's plenty of RAM.

#### Write to flash:
   * Request: ````40 0X XX XX YY````
       * XX XX XX is the starting address in flash memory for the write
       * YY is the count of bytes to write from the RAM buffer to flash
   * Response: ````41 0X XX XX YY````
      * After sending the response, we enter a timer-loop that counts down approximately 15 seconds, attempting a write each iteration until time runs out or it succeeds. SCI RX must be +20V for the write to succeed.
   * Success: ````22```` is echoed when YY bytes have been successfully written to flash memory
    * Failure:
       * Write error: ````0x01````
       * Timeout: ````0x80````
* **Note**:The expectation is a pattern of ````30 YY <bytes>```` to stage data to RAM, followed by a ````40 XX XX XX YY```` and a switch to +20V on SCI RX (switched off on 22/success) to write staged data to flash, followed by another 30, then 40, etc, etc.

### Bulk Read:
   * Request: ````45 0X XX XX YY YY````
       * 0X XX XX is a 20 bit address start address for the read
       * YY YY is a 16 bit count of bytes to return
   * Response: ````46 0X XX XX YY YY````
       * Response will be followed by ````YY YY```` count of bytes starting from ````0X XX XX````
   * Success: ````22````
   * **Note**: Too large of a ````YY YY```` value can cause unexpected problems on your recieving device.  Be cautious with large values
