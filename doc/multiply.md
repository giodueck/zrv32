# Multiplication of 32x32 bit numbers to get 64 bit result split in 2 registers

Worked example:

```
0x12345678 * 0x87654321 = 0x09A0CD05 70B88D78

0x5678 * 0x4321 = 0x16AC8D78

0x1234 * 0x4321 = 0x04C5F4B4

0x5678 * 0x8765 = 0x2DBB6558

0x1234 * 0x8765 = 0x09A09A84

Final =
09A0 9A84
     2DBB 6558
     04C5 F4B4
          16AC 8D78

09A0 CD05 70B8 8D78
```

Mul is just multiply and discard overflow to get lower word.

Mulh is multiply 4 halfwords with each other: ALBL, AHBL, ALBH, AHBH, then add (ALBL >> 16) + AHBL & 0xFFFF + ALBH & 0xFFFF, get the carry from that into C.
Finally, add AHBH + (AHBL >> 16) + (ALBH >> 16) + C to get high word.

## Extension to signed multiplication
https://en.wikipedia.org/wiki/Binary_multiplier#Signed_integers
