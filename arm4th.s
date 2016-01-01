# org = origin == start address of binary image, used to offset ip tokens
# tos = top of stack
# up = "user pointer" i.e. points to next
# rp = return stack pointer
# ip = "instruction" pointer (r12)
org .req r8
tos .req r9
up  .req r10
rp  .req r11

.text
.code 32

# Set the latest entry in the dictionary
.set latest,0

# Some macros to define words and codewords
# Credit to jonesforth for these macros: 
# http://git.annexia.org/?p=jonesforth.git;a=blob;f=jonesforth.S;h=45e6e854a5d2a4c3f26af264dfce56379d401425;hb=HEAD
.macro defword name,namelen,flags=0,label
.align 2
.global name_\label
name_\label:
.int latest               // link pointer
.set latest,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte \namelen            // 1 byte for length of name
.ascii "\name"            // name of the word
.align 2
.global \label
\label:
bl docol                  // forth words always start with a docol
.endm

# Define code words
.macro defcode name,namelen,flags=0,label
.align 2
.global name_\label
name_\label:
.int latest               // link pointer
.set latest,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte \namelen            // 1 byte for length of name
.ascii "\name"            // name of the word
.align 2
.global \label
\label:
.endm

# Store token of forth word in current location
.macro T label
.int \label
.endm

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

defcode "docol",5,,docol
  str   ip, [rp, #-4]!
  orr   ip, lr, #0
  bx    up

defcode "exit",4,,exit
  ldr   ip, [rp], #4
  bx    up

defcode "halt",4,,halt
  b     .

defword "init",4,,init
  T halt 

