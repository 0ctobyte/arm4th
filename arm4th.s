###############################################################################
# ASSEMBLER MACROS FOR CREATING FORTH DICTIONARY ENTRIES                      #
###############################################################################

# tos = top of stack
# up  = "user pointer", points to user area (i.e. data)
# org = origin == start address of binary image, used to offset ip tokens
# rp = return stack pointer
# ip = "interpreter" pointer (r12)
tos .req r8
up  .req r9
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
.balign 4
.global name_\label
name_\label:
.int link               // link pointer
.set link,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
.balign 4
.global \label
\label:                   // DTC Forth has a branch to enter as the codeword
bl enter                  // Forth words always start with enter
.endm

# Define code words
.macro defcode name,label,flags=0
.balign 4
.global name_\label
name_\label:
.int link               // link pointer
.set link,name_\label   // set link pointer to this word
.byte \flags              // 1 byte for flags
.byte (12346f - 12345f)   // 1 byte for length
12345:
.ascii "\name"            // name of the word
12346:
.balign 4
.global \label            // DTC Forth doesn't need a codeword here
\label:
.endm

# Define a variable
.macro defvar name,label,initial=0,flags=0
defcode \name,\label,\flags
  push  tos, sp
  add   tos, pc, #0x8
  next
.balign 4
var_\label:
.int \initial
.endm

# Define a constant
.macro defconst name,label,value,flags=0
defcode \name,\label,\flags
  push  tos, sp
  ldr   tos, [pc, #0x8]
  next
.balign 4
const_\label:
.int \value
.endm

.text
.code 32

###############################################################################
# START CODE                                                                  #
###############################################################################

# Minimal code for coldbooting Forth on an ARMv7 machine
.global _start
.balign 4
_start:
  # Set origin = 0x80010000 since this is where qemu loads the binary image
  movw  org, #0x0000
  movt  org, #0x8001

  # Set up to base of dram + 2k bytes
  movw  up, #0x800

  # Setup the stack pointer and return stack
  ldr   r0, =_start
  add   r0, r0, org
  mov   rp, r0
  sub   r0, r0, #0x400 // 1k return stack
  mov   sp, r0

  # tos magic value
  movw  r0, #0xbeef
  movt  r0, #0xdead
  mov   tos, r0

  # Finally set the ip to startforth
  ldr   ip, =startforth
  add   ip, ip, org

  # Go to init!
  next

# Start running the Forth interpreter
startforth:
  _xt tib
  _xt tibnum
  _xt accept
  _xt halt

###############################################################################
# FORTH INTERPRETER                                                           #
###############################################################################

# Enter a Forth word
defcode "enter",enter // ( -- )
  push  ip, rp
  mov   ip, lr
  next

# Exit a Forth word
defcode "exit",exit // ( -- )
  pop   ip, rp
  next

defconst "version",version,__VERSION      // Forth version
defconst "rp0",rpz,_start                 // Bottom of return stack
defconst "__enter",__enter,enter          // Address of enter routine
defconst "__f_immed",__f_immed,F_IMMED    // IMMEDIATE flag value
defconst "__f_hidden",__f_hidden,F_HIDDEN // HIDDEN flag value

defvar "here",here,__here          // Next free byte in dictionary
defvar "state",state,0             // Compile/Interpreter state
defvar "base",base,10              // Current base for printing/reading numbers
defvar "sp0",spz,_start-0x400      // Bottom of data stack 

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

defcode "halt",halt // ( -- )
  b     .

# Push the value at ip on the stack and increment ip by 4
defcode "lit",lit // ( -- )
  push  tos, sp
  ldr   tos, [ip], #4
  next

# Returns address to scratch space in memory. It's a constant offset from HERE
defcode "pad",pad // ( -- addr )
  bl    _pad_
  push  tos, sp
  mov   tos, r0
  next

defcode "_pad_",_pad_
  ldr   r0, var_here
  movw  r1, #0x100
  add   r0, r0, r1
  bx    lr

# Drop top of stack
defcode "drop",drop // ( c -- )
  pop   tos, sp
  next

# Swap tos with next element on stack
defcode "swap",swap // ( c0 c1 -- c1 c0 )
  mov   r0, tos
  pop   tos, sp
  push  r0, sp
  next

# Duplicate tos // ( c -- c c )
defcode "dup",dup
  push  tos, sp
  next

# Place second element on tos
defcode "over",over // ( c0 c1 -- c0 c1 c0 )
  push  tos, sp
  ldr   tos, [sp, #4]
  next

# Rotate the first three elements on the stack
defcode "rot",rot // ( c0 c1 c2 -- c2 c1 c0 )
  pop   r0, sp
  pop   r1, sp
  push  tos, sp
  push  r1, sp
  mov   tos, r0
  next

# Rotate the other way
defcode "-rot",nrot // ( c0 c1 c2 -- c2 c0 c1 )
  pop   r0, sp
  pop   r1, sp
  push  r0, sp
  push  tos, sp
  mov   tos, r1
  next

# Drop 2
defcode "2drop",twodrop // ( c0 c1 -- )
  pop   tos, sp
  pop   tos, sp
  next

# Duplicate top two elements
defcode "2dup",twodup // ( c0 c1 -- c0 c1 c0 c1 )
  ldr   r0, [sp]
  push  tos, sp
  push  r0, sp
  next

# Swap first two elements with next two
defcode "2swap",twoswap // ( c0 c1 c3 c4 -- c3 c4 c0 c1 )
  pop   r0, sp
  pop   r1, sp
  pop   r2, sp
  push  r0, sp
  push  tos, sp
  push  r2, sp
  mov   tos, r2
  next

# Duplicate top of stack if not zero
defcode "?dup",qdup // ( c ? -- c c | c )
  cmp   tos, #0
  strne tos, [sp, #-4]!
  next

# Increment value in tos
defcode "1+",incr // ( c -- c )
  add   tos, tos, #1
  next

# Decrement value in tos
defcode "1-",decr // ( c -- c )
  sub   tos, tos, #1
  next

# Add 4 to value in tos
defcode "4+",incr4 // ( c -- c )
  add   tos, tos, #4
  next

# Subtract 4 from value in tos
defcode "4-",decr4 // ( c -- c )
  sub   tos, tos, #4
  next

# Add top two values on stack
defcode "+",add // ( c0 c1 -- c2 )
  pop   r0, sp
  add   tos, tos, r0
  next

# Subtract top two values on stack
defcode "-",sub // ( c0 c1 -- c2 )
  pop   r0, sp
  sub   tos, r0, tos
  next

# Multiply
defcode "*",mul // ( c0 c1 -- c2 )
  pop   r0, sp
  mul   tos, tos, r0
  next

# Divide
defcode "/",div // ( c0 c1 -- c2 )
  pop   r0, sp
  udiv  tos, r0, tos
  next

# Modulo
defcode "mod",mod // ( c0 c1 -- c2 )
  pop   r0, sp
  mov   r1, tos
  udiv  tos, r0, tos 
  mul   tos, tos, r1
  sub   tos, r0, tos
  next

###############################################################################
# FORTH COMPARISON OPERATORS                                                  #
###############################################################################

defcode "=",equ // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvneq tos, tos
  next

defcode "<>",nequ // ( c0 c1 -- true | false ) 
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnne tos, tos
  next

defcode "<",lt // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnlt tos, tos
  next

defcode ">",gt // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvngt tos, tos
  next

defcode "<=",le // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnle tos, tos
  next

defcode ">=",ge // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnge tos, tos
  next

defcode "0=",zequ // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvneq tos, tos
  next

defcode "0<>",znequ // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnne tos, tos
  next

defcode "0<",zlt // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnlt tos, tos
  next

defcode "0>",zgt // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvngt tos, tos
  next

defcode "0<=",zle // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnle tos, tos
  next

defcode "0>=",zge // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnge tos, tos
  next

###############################################################################
# FORTH BITWISE OPERATORS                                                     #
###############################################################################

defcode "and",and // ( c0 c1 -- c2 )
  pop   r0, sp
  and   tos, r0, tos
  next

defcode "or",or // ( c0 c1 -- c2 )
  pop   r0, sp
  orr   tos, r0, tos
  next

defcode "xor",xor // ( c0 c1 -- c2 )
  pop   r0, sp
  eor   tos, r0, tos
  next

###############################################################################
# FORTH MEMORY OPERATIONS                                                     #
###############################################################################

defcode "!",store // ( val addr --  )
  pop   r0, sp
  str   r0, [tos]
  pop   tos, sp
  next

defcode "@",fetch // ( addr -- val )
  mov   r0, tos
  ldr   tos, [r0]
  next

defcode "+!",addstore // ( addr -- )
  pop   r0, sp
  ldr   r1, [tos]
  add   r0, r0, r1
  str   r0, [tos]
  pop   tos, sp
  next

defcode "-!",substore // ( addr -- )
  pop   r0, sp
  ldr   r1, [tos]
  sub   r0, r1, r0
  str   r0, [tos]
  pop   tos, sp
  next

# Store/Load Bytes
defcode "c!",storebyte // ( byte addr -- )
  pop   r0, sp
  strb  r0, [tos]
  pop   tos, sp
  next

defcode "c@",fetchbyte // ( addr -- byte )
  mov   r0, tos
  ldrb  tos, [r0]
  next

# Fetch byte from source and store byte to destination
defcode "c@c!",ccopy // ( src dest -- ) 
  pop   r0, sp
  ldrb  r1, [r0]
  strb  r1, [tos]
  pop   tos, sp
  next

# Block byte copy
defcode "cmove",cmove // ( src dest len -- )
  pop   r0, sp // destination
  pop   r1, sp // source
  mov   r2, tos // length
  pop   tos, sp
  bl    _cmove_
  next

defcode "_cmove_",_cmove_
_cmove__LOOP:
  ldrb  r3, [r1], #1
  strb  r3, [r0], #1
  subs  r2, r2, #1
  bne   _cmove__LOOP
  bx    lr

###############################################################################
# RETURN STACK MANIPULATION                                                   #
###############################################################################

defcode ">r",tor // ( c -- )
  push  tos, rp
  pop   tos, sp
  next

defcode "r>",fromr // ( -- c )
  push  tos, sp
  pop   tos, rp
  next

defcode "r@",rfetch // ( -- c )
  push  tos, sp
  ldr   tos, [rp]
  next

defcode "r!",rstore // ( c -- )
  str   tos, [rp]
  pop   tos, sp
  next

defcode "rdrop",rdrop // ( -- )
  pop   r0, rp
  next

###############################################################################
# STACK MANIPULATION                                                          #
###############################################################################

defcode "dsp@",spfetch // ( -- sp )
  push  tos, sp
  mov   tos, sp
  next

defcode "dsp!",spstore // ( sp -- )
  mov   r0, tos
  pop   tos, sp
  mov   sp, r0
  next

###############################################################################
# INPUT/OUTPUT                                                                #
###############################################################################

defconst "uart0",uart0,0x1c090000 // UART0 base address
defconst "uartdr",uartdr,0x0      // UART data register
defconst "uartfr",uartfr,0x18     // UART flag register

# Relevant bits in the UARTFR register
# uartfr_busy = 0x8  -> UART busy, set when TX FIFO is non-empty
# uartfr_rxfe = 0x10 -> RX FIFO is empty
# uartfr_txff = 0x20 -> TX FIFO is full
# uartfr_rxff = 0x40 -> RX FIFO is full
# uartfr_txfe = 0x80 -> TX FIFO is empty

defconst "tib",tib,0x100+0x80000000  // Location of text input buffer
defconst "tib#",tibnum,0x400         // 1k tib
defvar   ">in",toin,0x0              // Current parse area in tib

defconst "bl",bl,0x20 // space ascii character
defconst "bs",bs,0x08 // back space character
defconst "cr",cr,0x0d // carriage return
defconst "lf",lf,0x0a // line feed

defcode "emit?",emitq // ( -- true | false )
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  add   r1, r1, r2
  movw  r2, #0x20

  mov   r0, #0
  ldr   r3, [r1]
  ands  r3, r3, r2
  mvneq r0, r0

  push  tos, sp
  mov   tos, r0
  next

# Print character on stack to UART
defcode "emit",emit // ( char -- )
  mov   r0, tos
  pop   tos, sp
  bl    _emit_
  next

defcode "_emit_",_emit_
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  movw  r4, #0x20

  # Wait for TX FIFO to be not full
_emit__LOOP:
  ldr   r5, [r1, r2]
  ands  r5, r5, r4
  bne   _emit__LOOP
  
  # Put character in TX FIFO
  str   r0, [r1, r3]
  bx    lr

defcode "key?",keyq // ( -- true | false )
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  add   r1, r1, r2
  movw  r2, #0x10 

  mov   r0, #0
  ldr   r3, [r1]
  ands  r3, r3, r2
  mvneq r0, r0

  push  tos, sp
  mov   tos, r0
  next

# Read character from UART to stack
defcode "key",key // ( -- char )
  bl    _key_
  push  tos, sp
  mov   tos, r0
  next

defcode "_key_",_key_
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  movw  r4, #0x10

  # Wait for a character to be received
_key__LOOP:
  ldr   r5, [r1, r2]
  ands  r5, r5, r4
  bne   _key__LOOP

  # Read character from RX FIFO
  ldr   r0, [r1, r3]
  bx    lr

# Reads a string of characters from the input buffer delimited by 'char'
# places the address of the string on the stack, (the first word of the string contains
# the length of the string)
defcode "word",word // ( char -- addr )
  mov   r0, tos
  bl    _word_
  mov   tos, r0
  next

defcode "_word_",_word_
  push  lr, rp
  mov   r7, r0            // r7 = delimiter
  bl    _pad_
  add   r6, r0, #4        // r6 = pad
  push  r6, rp            // will need this later to calculate word size

  ldr   r1, const_tib     // r1 = tib address
  ldr   r4, =var_toin     // r4 = >in pointer
  ldr   r2, [r4]          // r2 = >in value
  ldr   r3, const_tibnum  // r3 = tib size

  # Skip leading delimiters
_word__skip_loop:
  # Check if end of TIB and exit with 0 length word
  cmp   r2, r3
  bge   _word__exit

  ldrb  r0, [r1, r2]
  add   r2, r2, #1
  
  # Check if delimiter and skip
  cmp   r0, r7
  beq   _word__skip_loop
  
  # Start reading characters into pad+4 
_word__read_loop:
  strb  r0, [r6], #1

  # Check if end of TIB and exit
  cmp   r2, r3
  bge   _word__exit

  ldrb  r0, [r1, r2]
  add   r2, r2, #1
  cmp   r0, r7
  bne   _word__read_loop

  # Calculate length and store it
_word__exit:
  pop   r0, rp
  sub   r6, r6, r0
  str   r6, [r0, #-4]!

  # Update >in
  str   r2, [r4]

  pop   lr, rp
  bx    lr

# Read in at most count chars from input to addr, stopping if a CR/LF is read
# Places the length of the string on the stack
defcode "accept",accept // ( addr count -- n )
  pop   r1, sp  // addr
  mov   r0, tos // count
  bl    _accept_
  mov   tos, r0
  next

defcode "_accept_",_accept_
  push  lr, rp

  mov   r7, r1 // addr
  mov   r6, r0 // max count

  movw  r0, #0
  push  r0, rp       // character count
  ldr   r0, const_bs // backspace
  push  r0, rp
  ldr   r0, const_cr // carriage return
  push  r0, rp

_accept__read_loop:
  ldr   r1, [rp, #8]
  cmp   r1, r6       // Reached max count?
  beq   _accept__exit

  bl    _key_
  bl    _emit_       // echo character
  
  ldr   r1, [rp, #8] // character count
  
  ldr   r2, [rp]
  cmp   r2, r0       // carriage return?
  beq   _accept__exit

  ldr   r2, [rp, #4]
  cmp   r2, r0       // backspace?
  subeq r7, r7, #1
  subeq r1, r1, #1
  str   r1, [rp, #8]
  beq   _accept__read_loop
 
  # Otherwise, store character in buffer and increment count
  add   r1, r1, #1
  str   r1, [rp, #8]
  strb  r0, [r7], #1
  b     _accept__read_loop

_accept__exit:
  ldr   r0, const_lf // Output line feed as well
  bl    _key_

  pop   r0, rp
  pop   r0, rp
  pop   r0, rp

  pop   lr, rp
  bx    lr

# Leave the address and length of string beginning at addr1 on the stack
defcode "count",count // ( addr1 -- addr2 n )
  mov   r0, tos
  bl    _count_
  mov   tos, r1
  push  r0, sp
  next

defcode "_count_",_count_
  ldr   r1, [r0]    // String length
  add   r0, r0, #4  // Actual string starting address
  bx    lr

defvar "latest",latest,name_latest // Last entry in Forth dictionary

.balign 4
__here:

