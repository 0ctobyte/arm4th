# tos = top of stack
# org = origin == start address of binary image, used to offset ip tokens
# up = "user pointer" i.e. points to next
# rp = return stack pointer
# ip = "instruction" pointer (r12)
tos .req r8
org .req r9
up  .req r10
rp  .req r11

.text
.code 32

# Set the latest entry in the dictionary
.set latest,0

# Store execution token of forth word in current location
.macro xt label
.int \label
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
.ascii "\name"            // name of the word
.byte 0                   // null terminate string
.align 2
.global \label
\label:
xt docol                  // forth words always start with a docol
.endm

# Define code words
.macro defcode name,label,flags=0
.align 2
.global name_\label
name_\label:
.int latest               // link pointer
.set latest,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.ascii "\name"            // name of the word
.byte 0                   // null terminate string
.align 2
.global \label
\label:
.int code_\label
.global code_\label
code_\label:
.endm


###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

# DOCOL is a special word that isn't part of the dictionary
# DOCOL doesn't have a codeword (i.e. code_docol) or any of the dictionary header
.align 2
.global docol
docol:
  str   ip, [rp, #-4]!
  add   ip, r0, #4
  bx    up

defcode "exit",exit
  ldr   ip, [rp], #4
  bx    up

defcode "halt",halt
  b     .

defword "init",init
  xt halt

