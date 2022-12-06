#!/usr/bin/env python3.10

import argparse
import os
from functools import partial
import signal
import serial
import time

parser = argparse.ArgumentParser(description='A basic ECU reader & writer for the SBEC3')
parser.add_argument('--device','-d', dest='serialDevice', action='store', default='/dev/ttyUSB0', help='The serial device to use (default: /dev/ttyUSB0)')
parser.add_argument('--baud', '-b', dest='Baud', action='store', default=62500, type=float, help='Connection baud rate (default: 62500)')
parser.add_argument('--bootloader', '-l', dest='bootloader', action='store', default="bootloader.bin", help='Bootloader image to use (default: bootloader.bin)')
parser.add_argument('--skip-bootstrap', '-s', dest='readyBS', action='store_const', const=True, default=False, help='If the ECU is already in bootstrap with a running bootloader, use this to skip handshake and upload (default: False)')
parser.add_argument('--write','-w', dest='binFile', action='store', help='The path and filename of the binary file to write to the ECU')
parser.add_argument('--writebuffer','-u', dest='bufferSize', action='store', type=int, default=2048,  help='The amount of ECU RAM to use for write buffer. (default: 2048)')
parser.add_argument('--read','-r', dest='dumpFile', action='store', default=None, help='Read the ECU flash and store it as DUMPFILE')
parser.add_argument('--read-partnum','-p', dest='rpartNum', action='store_const', const=True, default=None, help='Read and print the part number stored in the ECU EEPROM')
parser.add_argument('--write-partnum','-n', dest='wpartNum', action='store_const', const=True, default=None, help='Write a part number stored to the ECU EEPROM')
parser.add_argument('--read-vin','-v', dest='rvin', action='store_const', const=True, default=None, help='Read and print the VIN stored in the ECU EEPROM')
parser.add_argument('--write-vin','-i', dest='wvin', action='store_const', const=True, default=None, help='Write a VIN to the ECU EEPROM')
parser.add_argument('--flash-size', '-f', dest='flashsz', action="store", choices=['128', '256'], default='256', help='Flash firmware image size. MOST SBEC3 ECUs are 256K (default: 256)')
parser.add_argument('--erase', dest='eraseBank', action='store', choices=['0', '1', '2', '3', '4', 'ALL'], default=None, help='Erase Flash Bank [0,1,2,3,4|ALL], required prior to reprogramming (default: None)')
parser.add_argument('--read-serial', dest='readserial', action='store', default=None, type=int, help='Read READSERIAL bytes of data from the buffer and exit, used to read the output of raw commands.')
parser.add_argument('--send-serial', dest='sendserial', action='store', default=None, help='Write serial data to the device. Used to send raw commands. Follow with --read-serial # to read # bytes of the response')
parser.add_argument('--invert-rts', dest='invert_rts', action='store_const', const=True, default=False, help='Swap RTS hi / low if you are defaulting to RTS hi for some reason (default: False)')
parser.add_argument('--debug', dest='debug', action='store_const', const=True, default=False, help='Show lots of debug output')
args = parser.parse_args()

#Python sucks ass for bitwise math on bytes :-/
def solveSeed(seed):
   constVal = 9340
   seed = ((seed + constVal) | 5)
   if seed > 65536:
      seed = seed - 65536
   shiftcount = seed.to_bytes(2, 'big') # :-/
   i = shiftcount[1] & 15
   while i > 0:
      if (seed & 1):   
         seed = ((seed >> 1) | 32768)
      else:
         seed = seed >> 1;
      i = i - 1
   seed = seed | constVal
   return seed.to_bytes(2, 'big')

def checksum(message):
   csum = 0
   for bite in message:
     csum += bite
     if csum > 256:
        csum = csum - 256
   return csum

def handler(signum, frame):
    print("Exiting on ^C, cleaning up...") 
    ser.close()
    exit(1)

if args.invert_rts:
   rts_on = False
   rts_off = True
else:
   rts_on = True
   rts_off = False

signal.signal(signal.SIGINT, handler)

#loader = bytearray.fromhex("""4c010005DF""")
      
ser = serial.serial_for_url(args.serialDevice, do_not_open=True)
ser.rts = rts_off
ser.timeout = 3
ser.baudrate = args.Baud

try:
   ser.open()
   ser.rts = rts_off
except serial.SerialException as e:
   print('Could not open serial port {}: {}\n'.format(ser.name, e))
   exit(1)

print('Using device ' + ser.name + ' at', args.Baud, 'baud, 8N1')

if args.readyBS == False:  #the user says we're already bootstrapped, so skip the handshake and bootloader upload

   yn = input("Will apply 20V+ to SCI RX for bootstrap.  Ready? y/n/s(kip): ")
   if yn != 'n' and yn != 'y' and yn != 's':
      print("Expecting one of y, n, or s!  Exiting.")
      exit(1)
   elif yn == 'n':
      print("OK.  Exiting...")
      exit(0)
   elif yn == 's':
      print("Skipping bootstrap!")
      pass
   elif yn == 'y':
      ser.rts = rts_on
      print ("20V+ ON for 10 seconds. Turn key on now!")
      time.sleep(10)
      ser.rts = rts_off
      print ("20V+ OFF! Trying Magic Byte...")
      time.sleep(3)
      ser.read(4) #read until timeout to clear the buffer of bootup output

      # Handshake ?
      magicByte = bytes.fromhex('7f')
      ser.write(magicByte)
      response = ser.read(1)
      if response == b'':
         print("No response to Magic Byte.")
         exit(1)
      elif response.count(b'\x06') == 1:
         print(response.hex(), "Synced at", args.Baud, "baud")
      else:
         print("Unexpected response to Magic Byte: ", response.hex())
         exit(1)
      
      #Security seed
      seedReq = bytes.fromhex('24d027c1dc')
      seedResp = bytearray.fromhex('24d027c2')
      ser.write(seedReq)
      response = ser.read(7) #or timeout
      if response == b'':
         print("No response to seed request")
      elif response.count(b'\x26\xD0\x67\xC1') == 1: #hurrah.
         if args.debug:
            print(response.hex())
         seed = int.from_bytes(response[4:6], 'big')
         solution = solveSeed(seed=seed)
         print('Seed: ', seed.to_bytes(2, 'big').hex())
         print('Solution: ', solution.hex())
         seedResp.append(solution[0])
         seedResp.append(solution[1])
         csbyte = checksum(seedResp)
         seedResp.append(csbyte) #the entire response message with solved seed and checksum
         if args.debug:
            print(seedResp.hex())
         ser.write(seedResp)
         response = ser.read(7)
         if response.count(b'\x26\xd0\x67\xc2\x1f') == 1: #fuck yeah, bitches!
            print(response.hex(), "  Solution accepted!!!")
         else:
            print("Unexpected seed solution response: ", response.hex())
            exit(1)
      
      # Send reflash kernel
      bootloaderName = args.bootloader
      if not os.path.isfile(bootloaderName):
         print(bootloaderName, "does not exist!")
         exit(1)
      blSize = os.path.getsize(bootloaderName)
      preamble = bytearray.fromhex('4c0100')
      blSizeOffset = blSize + 255
      blSizeOffset = blSizeOffset.to_bytes(2, 'big')
      preamble.append(blSizeOffset[0])
      preamble.append(blSizeOffset[1])
      ser.write(preamble)
      response = ser.read(len(preamble))
      print("Uploading reflash kernel...")
      if args.debug:
         print("Sent     ", preamble.hex()) 
         print("Received ", response.hex())
      x = 0
      y = 32
      z = 32 #32 byte chunks
      with open(bootloaderName, 'rb') as f:
         for block in iter(partial(f.read, 32), b''): #block is a 32byte chunk of $file
           if args.debug:
              print("X",x, "Y",y, "Z",z)
           ser.write(block)
           response = ser.read(z)
           if args.debug:
              print("Sent     ", block.hex()) 
              print("Received ", response.hex())
           x += z
           y += z
           if y >= blSize:  # Don't run off the end
              y = blSize 
      print("Booting reflash kernel...")
      bootcmd = bytes.fromhex('470100')
      ser.write(bootcmd)
      response = ser.read(4)
      if response.count(b'\x47\x01\x00\x22') == 1:  #Success!
         print(response.hex(), " Kernel running!")
         ser.write(b'\x10')
         response = ser.read(1)
         if response == b'\x11':
            print(response.hex(), " Kernel alive!")
      else:
         print("Kernel boot failed, response: ",response.hex())

# Commands ...!
if args.dumpFile is not None:
   fileName = args.dumpFile 
   print("Running bootloader bulk dump command, saving to " + fileName)
   if os.path.isfile(fileName):
      yn = input(fileName+" Already exists. Overwrite? y/n")
      if yn == 'y':
         pass
      else:
         exit(1)
   if args.flashsz == '128':
      imageSize = 131071
   else:
      imageSize = 262143
   bytesRead = bytearray()
   #45 0X XX XX YY YY
   y = 0  # start
   z = 64 # bytes per request
   zB = z.to_bytes(2, 'big') # YY YY
   while y < imageSize:
      offsetY = y + 262144; # "start" is 0, but the firmware is at 0x40000-0x7FFFF
      offsetY = offsetY.to_bytes(3, 'big') # XX XX XX
      if args.debug:
         print("Y",y, "Z",z, "OffsetY",offsetY.hex())
      dumpCmd = bytearray.fromhex('45')
      dumpCmd.append(offsetY[0])
      dumpCmd.append(offsetY[1])
      dumpCmd.append(offsetY[2])
      dumpCmd.append(zB[0])
      dumpCmd.append(zB[1])
      ser.write(dumpCmd)
      response = ser.read(6)
      if args.debug:
         print("Dump command : ",dumpCmd.hex())
         print("Dump response: ",response.hex())
      if response[0] != 70:
         print("Unexpected response to dump command: ", response.hex())
         exit(1) 
      response = ser.read(z)
      if args.debug:
         print(len(response))
         print(response.hex())
      i = 1
      for bite in response:
         bytesRead.append(bite)
      if args.debug:
         print(len(bytesRead))
      y += z
      if y > imageSize: # don't run off the end
         y = imageSize

   # Now we have the flash image in bytesRead, write it to a file dumpFile
   binary_file = open(fileName, "wb") 
   binary_file.write(bytesRead)
   binary_file.close()
   print("Wrote", y, "bytes to " + fileName)
   ser.close()
   exit(0)

if args.eraseBank is not None:
   args.eraseBank = args.eraseBank.upper()
   if args.eraseBank == 'ALL':
      args.eraseBank = [0, 1, 2, 3, 4]
   for bank in args.eraseBank:
      cmd20 = bytearray.fromhex('20') #build the command
      cmd20r = bytearray.fromhex('21') #build the expected response
      print("Bank:",bank)
      if bank == 0 or bank == '0':
         eraseBank = bytearray.fromhex('040000')
      elif bank == 1 or bank == '1':
         eraseBank = bytearray.fromhex('044000')
      elif bank == 2 or bank == '2':
         eraseBank = bytearray.fromhex('046000')
      elif bank == 3 or bank == '3':
         eraseBank = bytearray.fromhex('048000')
      elif bank == 4 or bank == '4':
         eraseBank = bytearray.fromhex('060000')
      else:
         print("Bank must be 0 to 4 or \"all\", exiting...")
         exit(1)
      for addr in eraseBank:
         cmd20.append(addr)
         cmd20r.append(addr)
      if args.debug:
         print(cmd20.hex())
      yn = input("Erasing Bank"+str(bank)+" 'y' to confirm: ")
      if yn == 'y':
         pass
      else:
         exit(1)
      ser.write(cmd20)
      response = ser.read(4)
      if args.debug:
         print("Command :", cmd20.hex())
         print("Response:", response.hex())
      if response.count(cmd20r) != 1:
         print("Unexpected response to erase command", response.hex())
         exit(1)
      else:
         print("Erase bank", bank, "command sent, applying programming voltage...")
         ser.timeout = 40 # this is longer then the bootloader's timeout so we catch the response
         ser.rts = rts_on
         response = ser.read(1)
         ser.timeout = 3
         ser.rts = rts_off
         if response == b'\x80':
            print("Erase bank", bank, "command timed out, check programming voltage?")
         elif response == b'\x22':
            print("Erase command on", bank," successful!")
         else:
            print("Unexpected response to erase command: ", response.hex()) 
         
# Write
if args.binFile is not None:
   bufferSize = args.bufferSize
   if not os.path.isfile(args.binFile):
      print(args.binFile, "does not exist!")
      exit(1)
   if os.path.getsize(args.binFile) > 262144:
      print("File size is greater than 256K, I don't know what to do with that.")
      exit(1)
   if args.bufferSize > 3072:
      print("Maximum buffer size is 3072 bytes (to leave space for the bootloader and stack)")
      exit(1)
   if args.bufferSize % 2:
      bufferSize += 1  # needs to be whole words
      print("Adjusting buffersize to",bufferSize)
   stageBytes = bufferSize.to_bytes(2, 'big')
      
# get the size of the file
# if it's bigger than 262144 say no.
# send 30 07 FF to stage 2048 bytes
# iterate over the file and send 64byte chunks until we get a 22 back
# repeat
   blkcount = 1
   targetAddr = 262144  #someday I'll try to do this by bank; this is an int so I can do simple addition on it.
   endAddr = 524288   # 0x40000 - 0x80000
   cmd30 = bytearray.fromhex('30')
   cmd30r = bytearray.fromhex('31') 
   for bite in stageBytes:
      cmd30.append(bite)
      cmd30r.append(bite)
   with open(args.binFile, 'rb') as f:
      for block in iter(partial(f.read, bufferSize), b''): #block is a bufferSize chunk of $file
         x = 0  #head index
         y = 64 #tail index 
         z = 64 #TX chunk size
         ser.write(cmd30)
         response = ser.read(3)
#         response = cmd30r
         if args.debug:
            print("CMD30 Buffer Size:", args.bufferSize)
            print("CMD30 Blocklen   :", len(block))
            print("CMD30 Command    :", cmd30.hex())
            print("CMD30 Response   :", response.hex())
         if response.count(cmd30r) != 1: #we're good, send bufferSize bytes along
            print("Unexpected response to data staging command: ", response.hex())
            exit(1)
         else:
            while x <= len(block):
               chunk = block[x:y]
               if args.debug:
                  print("X",x, "Y",y, "Z",z)
               ser.write(chunk)
               if args.debug:
                  print("CHUNKLEN:", len(chunk))
                  print("CMD30 TX:",chunk.hex())
               x += z
               y += z
               if y >= len(block):  # Don't run off the end
                  y = len(block)
            response = ser.read(1)
#            response = b'\x22'
            if response != b'\x22':
               print("Unexpected response when staging data: ",response.hex())
               exit(1)
            else:
               print("Transferred",bufferSize,"bytes to RAM buffer")
               if args.debug:
                  print("Data staged, attempting to program...")
               cmd40 = bytearray.fromhex('40')
               cmd40r = bytearray.fromhex('41')
               addrBytes = targetAddr.to_bytes(3,'big')   #e.g. "04 00 00"
               sizeBytes = args.bufferSize.to_bytes(2,'big')   #e.g. "07 FF"
               for bite in addrBytes:
                  cmd40.append(bite)
                  cmd40r.append(bite)
               for bite in sizeBytes:
                  cmd40.append(bite)
                  cmd40r.append(bite)
               if args.debug:
                  ending = targetAddr + args.bufferSize
                  endByte = ending.to_bytes(3,'big')
                  print("Program starting addr: ",addrBytes.hex())
                  print("Program ending addr  : ",endByte.hex())
                  print("CMD40:",cmd40.hex())
               print("Programming buffer block", blkcount, "@",addrBytes.hex()," ... ", end = '')
               blkcount += 1
               ser.write(cmd40)
               response = ser.read(6)
#               response = cmd40r
               if response.count(cmd40r) != 1:
                  print("Unexpected response to program address command: ", response.hex())
                  exit(1)
               else:
                  ser.timeout = 40 #long enough to catch the bootloader response on timeout
                  ser.rts = rts_on
                  response = ser.read(1)
                  ser.rts = rts_off
                  ser.timeout = 3
#                  response = b'\x22'
                  if response == b'\x80':
                     print("Program addr", addrBytes.hex(), "timed out, check programming voltage?")
                     exit(1)
                  elif response == b'\x22':
                     print("Program addr", addrBytes.hex(), "successful!")
                     print("")
                  else:
                     print("Unexpected response to program command: ", response.hex())
                     exit(1)
                  targetAddr += bufferSize #increment targetAddr by the size of the buffer
                  if targetAddr > endAddr:
                     targetAddr = endAddr
                  time.sleep(1)
        
if args.wpartNum is not None:
   pnOne = bytearray.fromhex('5501f0')
   pnTwo = bytearray.fromhex('5501f2')
   askPN = input("Provide a new 4 byte / 8 digit part number and press Enter:")
   if len(askPN) != 8:
      print("Part number must be exactly 8 characters long!")
      exit(1)
   partNumber = bytearray.fromhex(askPN)
   pnOne.append(partNumber[0])
   pnOne.append(partNumber[1])
   pnTwo.append(partNumber[2]) 
   pnTwo.append(partNumber[3]) 
   ser.write(pnOne)
   response = ser.read(7)
   if response.count(b'\x56\x01\xf0') != 1:
      print("Unexpected response to EEPROM write command: ", response.hex())
      exit(1)
   ser.write(pnTwo)
   response = ser.read(7)
   if response.count(b'\x56\x01\xf2') != 1:
      print("Unexpected response to EEPROM write command: ", response.hex())
      exit(1)
   print("Wrote part number to EEPROM: ",partNumber.hex())

if args.rpartNum is not None:
   pnOne = bytes.fromhex('5001f0')
   pnTwo = bytes.fromhex('5001f2')
   partNumber = bytearray()
   ser.write(pnOne)
   response = ser.read(5)
   if response.count(b'\x51\x01\xf0') != 1:
      print("Unexpected response to EEPROM read command: ", response.hex())
      exit(1)
   else:
      partNumber.append(response[3])
      partNumber.append(response[4])
   ser.write(pnTwo)
   response = ser.read(5)
   if response.count(b'\x51\x01\xf2') != 1:
      print("Unexpected response to EEPROM read command: ", response.hex())
      exit(1)
   else:
      partNumber.append(response[3])
      partNumber.append(response[4])
   print("Part number from EEPROM: ",partNumber.hex())
   exit(0)

if args.wvin is not None:
   vinOffsets = bytearray.fromhex('626466686a6c6e7072')
   cmd55 = bytes.fromhex('5500')
   cmd55r = bytes.fromhex('5600')
   askVin = input("Provide a new 17 character VIN and press Enter:")
   if len(askVin) != 17:
      print("VIN must be exactly 17 charaters long!")
      exit(1)
   vinBytes = bytearray(askVin, 'utf8')
   vinBytes.append(255) #padding out to 18 bytes
   thisSlice = 0
   if args.debug:
      print("vinBytes:"+vinBytes.hex())
   for bite in vinOffsets:
      vinWord = vinBytes[thisSlice:(thisSlice+2)]
      thisCommand = bytearray(cmd55)
      thisResponse = bytearray(cmd55r)
      thisCommand.append(bite)
      thisCommand.append(vinWord[0])
      thisCommand.append(vinWord[1])
      thisResponse.append(bite)
      thisResponse.append(vinWord[0])
      thisResponse.append(vinWord[1])
      thisResponse.append(vinWord[0])
      thisResponse.append(vinWord[1])
      ser.write(thisCommand)
      response = ser.read(7)
      if args.debug:
         print("          Command: ",thisCommand.hex())
         print("Expected response: ",thisResponse.hex())
         print("Received response: ",response.hex())
      if response.count(thisResponse) != 1 and response.count(vinWord) != 2:
         print("Unexpected response to EEPROM write command: ", response.hex())
         exit(1)
      thisSlice += 2
   print("Wrote VIN ",askVin,"to EEPROM.  Read VIN back to verify.")

if args.rvin is not None:
   vinOffsets = bytearray.fromhex('626466686a6c6e7072')
   cmd50 = bytes.fromhex('5000')
   cmd50r = bytes.fromhex('5100')
   vin = bytearray()
   for bite in vinOffsets:
      thisCommand = bytearray(cmd50)
      thisResponse = bytearray(cmd50r)
      thisCommand.append(bite)
      thisResponse.append(bite)
      ser.write(thisCommand)
      response = ser.read(5)
      if args.debug:
         print("          Command: ",thisCommand.hex())
         print("Expected response: ",thisResponse.hex())
         print("Received response: ",response.hex())
      if response.count(thisResponse) != 1:
         print("Unexpected response to EEPROM read command: ", response.hex())
         exit(1)
      else:
         vin.append(response[3])
         vin.append(response[4])            
   print("Vehicle Identification Number from EEPROM: ",vin[0:17].decode('utf8', errors='replace')) #chop off the last byte

if args.sendserial is not None:
   time.sleep(1)
   send = bytes.fromhex(str(args.sendserial))
   ser.write(send)
   print("Transmit:", send.hex())

if args.readserial is not None:
   time.sleep(1)
   response = ser.read(args.readserial)
   print("Receive :", response.hex())
