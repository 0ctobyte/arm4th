# tos = top of stack
# org = origin == start address of binary image, used to offset ip tokens
# rp = return stack pointer
# ip = "interpreter" pointer (r12)
tos .req r9
org .req r10
rp  .req r11

# Set the latest entry in the dictionary
.set link,0

.set __VERSION,1
.set F_IMMED,0x80
.set F_HIDDEN,0x40

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
.int link               // link pointer
.set link,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
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
.int link               // link pointer
.set link,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
.align 2
.global \label            // DTC Forth doesn't need a codeword here
\label:
.endm

# Define a variable
.macro defvar name,label,initial=0,flags=0
defcode \name,\label,\flags
  push  tos, sp
  ldr   tos, =var_\label
  add   tos, tos, org
  next
.align 2
var_\label:
.int \initial
.endm

# Define a constant
.macro defconst name,label,value,flags=0
defcode \name,\label,\flags
  push  tos, sp
  ldr   tos, const_\label
  next
.align 2
const_\label:
.int \value
.endm

