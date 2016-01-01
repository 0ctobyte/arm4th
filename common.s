# tos = top of stack
# org = origin == start address of binary image, used to offset ip tokens
# rp = return stack pointer
# ip = "interpreter" pointer (r12)
tos .req r9
org .req r10
rp  .req r11

# Set the latest entry in the dictionary
.set latest,0

# Store execution token of forth word in current location
.macro _xt label
.int \label
.endm

# Inline NEXT macro
.macro next
  ldr   r0, [ip], #4
  add   r0, r0, org
  bx    r0
.endm

# push and pop macros
.macro push reg,sp
  str   \reg, [\sp, #-4]!
.endm

.macro pop reg,sp
  ldr   \reg, [\sp], #4
.endm
  

# Some macros to define words and codewords
# Credit to jonesforth for these macros: 
# http://git.annexia.org/?p=jonesforth.git;a=blob;f=jonesforth.S;h=45e6e854a5d2a4c3f26af264dfce56379d401425;hb=HEAD
.macro defword name,label,flags=0
.align 2
.global name_\label
name_\label:
.int latest               // link pointer
.set latest,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
.byte 0                   // null terminate string
.align 2
.global \label
\label:                   // DTC Forth has a branch to enter as the codeword
bl enter                  // Forth words always start with enter
.endm

# Define code words
.macro defcode name,label,flags=0
.align 2
.global name_\label
name_\label:
.int latest               // link pointer
.set latest,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
.byte 0                   // null terminate string
.align 2
.global \label            // DTC Forth doesn't need a codeword here
\label:
.endm

