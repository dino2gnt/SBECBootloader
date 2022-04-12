#!/usr/bin/env python3.9

import argparse
import os
from functools import partial
import signal
import serial
import time

parser = argparse.ArgumentParser(description='A basic ECU reader & writer for the SBEC3')
parser.add_argument('--device','-d', dest='serialDevice', action='store', default='/dev/ttyUSB0', help='The serial device to use (default: /dev/ttyUSB0)')
parser.add_argument('--baud', '-b', dest='Baud', action='store', default=62500, type=int, help='Connection baud rate (default: 62500)')
parser.add_argument('--already-bootstrapped', '-a', dest='readyBS', action='store', default=False, help='If the ECU is already in bootstrap with a running bootloader, use this to skip handshake and upload (default: False)')
parser.add_argument('--write','-w', dest='binFile', action='store', help='The path and filename of the binary file to write to the ECU')
parser.add_argument('--writebuffer','-u', dest='bufferSize', action='store', type=int, default=2048,  help='The amount of ECU RAM to use for write buffer. (default: 2048)')
parser.add_argument('--read','-r', dest='dumpFile', action='store', default=None, help='Read the ECU flash and store it as DUMPFILE')
parser.add_argument('--partnum','-p', dest='partNum', action='store', help='Read and print the part number stored in the ECU')
parser.add_argument('--256k', dest='eeprom256', action='store', default='True', help='256K firmware image (default: True)')
parser.add_argument('--128k', dest='eeprom128', action='store', default='False', help='128K firmware image (default: False)')
parser.add_argument('--erase', dest='eraseBank', action='store', default=None, help='Erase Flash Bank [0,1,2,3,4|ALL], required prior to reprogramming (default: None)')
parser.add_argument('--read-serial', dest='readserial', action='store', default=None, type=int, help='Read READSERIAL bytes of data from the buffer and exit')
parser.add_argument('--send-serial', dest='sendserial', action='store', default=None, help='Write SENDSERIAL bytes of data to the device and exit')
parser.add_argument('--debug', dest='debug', action='store', default=False, help='Show lots of debug output')
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

signal.signal(signal.SIGINT, handler)

#loader = bytearray.fromhex('4c010004E937800290fa00013cf810b7f4f8203787009af83037870152f84037870196f84537870030b6da17657c0c7601b7f417ea7c0f37b50043fa00014c27f717657c0d76427840b6f217e57c0f27f737b00001b6f627f7274cf546fa000126fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01ad17fc01acfa000126fa00013c17fa0154fa000126fa00013c17fa0155fa000126c500fa0001263c0127310154b6ee3780ff56274cf521fa000126fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01adfa00012617fc01acfa000260fa00024a37b5001f37fa02962a107922000efa00024afa00023427310296b718fa00023cfa00022a37b60080b7dafa00022a37b60078b6d0f522b000fa00022afa000126fa0002343780fed837b500708a00850027f737b500508a0027f737b500208a0037b500d08a0027f737e5790a37b1f42437ea791617e579222810792227f71725791ef50617ea792127f7f531fa000126fa000298fa0003782775fa00013c27da7c0127310296b6ee2775f522fa0001263780fe6c274cfa00013c17fa0296fa000126fa00013c17fa0297fa0001262733029627f7f541fa000126fa00034afa000378fa000234fa000260fa00024a37b5001f37fa01ac2a107922000efa00024afa000234273101acb748fa00022a37b60080b7de279537b8ffffb71c37b50040278a2795278afa00022a37b60078b6c27c0237780296b6aaf522b018fa00034227852790b6042785fa000382b0defa000342f501b0fef580fa0001263780fdc037b500ff278a27f7fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01adfa000126fa00029817fc01ac277527f7f500379d37bd039627f717fa01543717fa00012617f50154fa00012627f7373b00e0f50f379e37be8000f500379f37bf07f617e57a02f883b70037bf0ff6371527fa379d37b5014837ea7a0028807a2137b500cf37ea7a4437b5040537ea7a4837ea7a4c37b568f037ea7a4a37b570f037ea7a4e37b5ff8837ea7a5437b5783037ea7a5637b5f88137ea081437e5081237b7000137ea081237b5000037ea081827290806ffff2729080803ff27f53735082427aa7c0437380838b3f417257920272808602000fa00044cf522fa0001263780fcb637b5408837ea7c007506176a7c0475fe176a7c057533176a7c1675f8176a7c1575fe176a7c1737b5810837ea7c1837b5100037ea7c1a37b5000037ea7c1c7500176a7c1e37354242376a7d4137350202376a7d433735c202376a7d453735c242376a7d4837b5010037ea7d2437b5020237ea7c1cfa0004c627f728807c1f29807c1a37053701b70a2a807c1ffff628807c1f3706b002373b010037fc27f7')
#loader = bytearray.fromhex('4c010004d33780027afa00013cf810b7f4f8203787009af83037870152f84037870196f84537870030b6da17657c0c7601b7f417ea7c0f37b50043fa00014c27f717657c0d76427840b6f217e57c0f27f737b00001b6f627f7274cf546fa000126fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01ad17fc01acfa000126fa00013c17fa0154fa000126fa00013c17fa0155fa000126c500fa0001263c0127310154b6ee3780ff56274cf521fa000126fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01adfa00012617fc01acfa000260fa00024a37b5001f37fa02962a107922000efa00024afa00023427310296b718fa00023cfa00022a37b60080b7dafa00022a37b60078b6d0f522b000fa00022afa000126fa0002343780fed837b500708a00850027f737b500508a0027f737b500208a0037b500d08a0027f737e5790a37b1f42437ea791617e579222810792227f71725791ef50617ea792127f7f531fa000126fa000298fa0003722775fa00013c27da7c0127310296b6ee2775f522fa0001263780fe6c274cfa00013c17fa0296fa000126fa00013c17fa0297fa0001262733029627f7f541fa000126fa000344fa000372fa000234fa000260fa00024a37b5001f37fa01ac2a107922000efa00024afa000234273101acb742fa00022a37b60080b7de279537b8ffffb71c37b50040278a2795278afa00022a37b60078b6c27c0237780296b6aaf522b012fa00033c27852790b6feb0e4fa00033cf501b0fef580fa0001263780fdc637b500ff278a27f7fa00013c379cfa000126fa00013c17fa01acfa000126fa00013c17fa01adfa000126fa00029817fc01ac277527f7f500379d37bd038027f7274c274c373b00e0f50f379e37be8000f500379f37bf07f617e57a02f883b70037bf0ff6371527fa379d37b5014837ea7a0028807a2137b500cf37ea7a4437b5040537ea7a4837ea7a4c37b568f037ea7a4a37b570f037ea7a4e37b5ff8837ea7a5437b5783037ea7a5637b5f88137ea081437e5081237b7000137ea081237b5000037ea081827290806ffff2729080803ff27f53735082427aa7c0437380838b3f417257920272808602000fa000436f522fa0001263780fccc37b5408837ea7c007506176a7c0475fe176a7c057533176a7c1675f8176a7c1575fe176a7c1737b5810837ea7c1837b5100037ea7c1a37b5000037ea7c1c7500176a7c1e37354242376a7d4137350202376a7d433735c202376a7d453735c242376a7d4837b5010037ea7d2437b5020237ea7c1cfa0004b027f728807c1f29807c1a37053701b70a2a807c1ffff628807c1f3706b002373b010037fc27f7')
loader = bytearray.fromhex("""4c010004d937800280fa000144f810b716f820378700a2f8303787015af8403787019af84537870038b6daf511fa00012eb7d217657c0c7601b7f417ea7c0f37b50043fa00
015427f717657c0d76427840b6f217e57c0f27f737b00001b6f627f7274cf546fa00012efa000144379cfa00012efa00014417fa01b4fa00012efa00014417fa
01b517fc01b4fa00012efa00014417fa015cfa00012efa00014417fa015dfa00012ec500fa00012e3c012731015cb6ee3780ff4e274cf521fa00012efa000144
379cfa00012efa00014417fa01b4fa00012efa00014417fa01b5fa00012e17fc01b4fa000268fa00025237b5001f37fa029e2a107922000efa000252fa00023c
2731029eb718fa000244fa00023237b60080b7dafa00023237b60078b6d0f522b000fa000232fa00012efa00023c3780fed037b500708a00850027f737b50050
8a0027f737b500208a0037b500d08a0027f737e5790a37b1f42437ea791617e579222810792227f71725791ef50617ea792127f7f531fa00012efa0002a0fa00
037c2775fa00014427da7c013778029eb6ee2775f522fa00012e3780fe64274cfa00014417fa029efa00012efa00014417fa029ffa00012e27f7f541fa00012e
fa00034efa00037cfa00023cfa000268fa00025237b5001f37fa01b42a107922000efa000252fa00023c273101b4b748fa00023237b60080b7de279537b8ffff
b72037b50040278a2795278afa00023237b60078b6c27c023778029eb6aafa000346f522b014fa00034627852790b6002785b0defa000346f501b0fef580fa00
012e3780fdbc37b500ff278a27f7fa000144379cfa00012efa00014417fa01b4fa00012efa00014417fa01b5fa00012efa0002a017fc01b4277527f7f500379d
37bd038627f7373b00e0f50f379e37be8000f500379f37bf07f617e57a02f883b70037bf0ff6371527fa379d37b5014837ea7a0028807a2137b500cf37ea7a44
37b5040537ea7a4837ea7a4c37b568f037ea7a4a37b570f037ea7a4e37b5ff8837ea7a5437b5783037ea7a5637b5f88137ea081437e5081237b7000137ea0812
37b5000037ea081827290806ffff2729080803ff27f53735082427aa7c0437380838b3f417257920272808602000fa00043cf522fa00012e3780fcc637b54088
37ea7c007506176a7c0475fe176a7c057533176a7c1675f8176a7c1575fe176a7c1737b5810837ea7c1837b5100037ea7c1a37b5000037ea7c1c7500176a7c1e
37354242376a7d4137350202376a7d433735c202376a7d453735c242376a7d4837b5010037ea7d2437b5020237ea7c1cfa0004b627f728807c1f29807c1a3705
3701b70a2a807c1ffff628807c1f3706b002373b010037fc27f7""")
      
ser = serial.serial_for_url(args.serialDevice, do_not_open=True)
ser.rts = False
ser.timeout = 3
ser.baudrate = args.Baud

try:
   ser.open()
except serial.SerialException as e:
   sys.stderr.write('Could not open serial port {}: {}\n'.format(ser.name, e))
   sys.exit(1)

print('Using device ' + ser.name + ' at', args.Baud, 'baud, 8N1')

if args.readyBS == False:  #the user says we're already bootstrapped, so skip the handshake and bootloader upload

   yn = input("Applying 20V+ to SCI RX.  Ready? y/n: ")
   if yn != 'n':
      ser.rts = True
      print ("20V+ ON for 10 seconds. Turn key on now!")
      time.sleep(10)
      ser.rts = False
      print ("20V+ OFF! Trying Magic Byte...")
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
      print("Uploading reflash kernel...")
      x = 0
      y = 16
      z = 16 #16 byte chunks
      while x < len(loader):
         chunk = loader[x:y]
         if args.debug:
            print("X",x, "Y",y, "Z",z)
         ser.write(chunk)
         response = ser.read(z)
         if args.debug:
            print("Sent     ", chunk.hex()) 
            print("Received ", response.hex())
         x += z
         y += z
         if y >= len(loader):  # Don't run off the end
            y = len(loader) 
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
   if args.eeprom128 == True:
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
         ser.rts = True
         response = ser.read(1)
         ser.timeout = 3
         ser.rts = False
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
                  ser.rts = True
                  response = ser.read(1)
                  ser.rts = False
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
        
if args.sendserial is not None:
   time.sleep(1)
   send = bytes.fromhex(str(args.sendserial))
   ser.write(send)
   print("Transmit:", send.hex())

if args.readserial is not None:
   time.sleep(1)
   response = ser.read(args.readserial)
   print("Receive :", response.hex())
