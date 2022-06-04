#!/usr/bin/env python3.9

import argparse
import os
import signal

parser = argparse.ArgumentParser(description='Calculate and optionally store checksum for an SBEC3 firmware image')
parser.add_argument('--binfile', '-b', dest='binFile', action='store', default=None, required=True, help='The firmware image to work on')
parser.add_argument('--write-checksum', '-w', dest='write', action='store_const', const=True, default=False, help='Write the checksum to the firmware image. (default False)')
parser.add_argument('--debug', dest='debug', action='store_const', const=True, default=False, help='Show lots of debug output')
args = parser.parse_args()

def handler(signum, frame):
    print("Exiting on ^C, cleaning up...")
    ser.close()
    exit(1)
signal.signal(signal.SIGINT, handler)

def calcChecksum(file):

    byte = file.read(1)
    csum = 0;
    while byte:
       csum += int.from_bytes(byte, "big")
       if csum > 255:
          csum = csum - 256 
       byte = file.read(1) 
    return csum.to_bytes(1, 'big')

def readChecksumValues(file,offset):
    file.seek(3 + offset); #0x305
    csumByte1 = file.read(1);
    file.seek(13 +  offset); #0x30F
    csumByte2 = file.read(1);
    file.seek(0);

    return csumByte1, csumByte2

def readChecksumOffset(file):
    file.seek(514); #0x203
    csumByte1 = file.read(1);
    file.seek(515); #0x203
    csumByte2 = file.read(1);
    file.seek(0);
    offset = int.from_bytes(csumByte1, "big")
    offset = offset << 8
    offset += int.from_bytes(csumByte2, "big")

    return offset

def calcNewChecksum(checksum, csumByte1, csumByte2):
    sumDiff = int.from_bytes(csumByte1,"big") - int.from_bytes(checksum,"big")
    if sumDiff < 0:
       sumDiff = sumDiff * -1
       newCorrectionByte = int.from_bytes(csumByte2, "big") - sumDiff
    else:
       newCorrectionByte = int.from_bytes(csumByte2, "big") + sumDiff
    if newCorrectionByte < 0:
       newCorrectionByte = 256 + newCorrectionByte
    if newCorrectionByte > 256:
       newCorrectionByte = newCorrectionByte - 256
    
    return newCorrectionByte.to_bytes(1, 'big')

def writeCorrectionByte(f, correction, offset):
    f.seek(13 + offset)
    f.write(correction)
    f.flush()

if args.binFile is not None:
   if not os.path.isfile(args.binFile):
      print(args.binFile, "does not exist!")
      exit(1)

   f = open(args.binFile, "r+b")
   offset = readChecksumOffset(f)
   checksum = calcChecksum(f)
   csumByte1, csumByte2 = readChecksumValues(f, offset)
   correction = calcNewChecksum(checksum, csumByte1, csumByte2)

   if args.debug:
      print("Offset: ", hex(offset))
      print("Read Checksum Byte     = ", csumByte1.hex())
      print("Read Correction Byte   = ", csumByte2.hex())
      print("Calculated checksum    = ", checksum.hex())
      print("Calculated correction  = ", correction.hex())

   if csumByte1 == checksum:
      print("Checksum matches!")
      print("Read:",csumByte1.hex(), csumByte2.hex()," Calculated:",checksum.hex(), correction.hex())
      exit(0)
   else:
      print("Checksum doesn't match, correction byte",csumByte2.hex(), "should be",correction.hex(),"!")

   if args.write:
      writeCorrectionByte(f,correction, offset)
      f.close()
      f = open(args.binFile, "rb")
      print("Wrote correction byte",correction.hex(),", verifing checksum...")
      newChecksum = calcChecksum(f)
      if args.debug:
         print("New checksum:",newChecksum.hex())
         print("checksum byte:",csumByte1.hex())
      csumByte1, csumByte2 = readChecksumValues(f, offset)
      if csumByte1 == newChecksum:
         print("Checksum matches!")
         print("Read:",csumByte1.hex(), csumByte2.hex()," Calculated:",newChecksum.hex(), correction.hex())
      else:
         print("Checksum check failed, we messed up somewhere!")
         exit(1)
   f.close()
   exit(0)
