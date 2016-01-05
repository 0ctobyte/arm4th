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
#if BBB
  # For the BeagleBoneBlack disable the WDT
  bl    _disable_wdt_

  # Enable the vfpu
  bl    _enable_vfpu_

  # enable the UART FIFO on the BeagleBone
  movw  r0, #0x1
  ldr   r1, const_uart0
  str   r0, [r1, #0x8]
#endif
  
  # Set origin
  ldr   org, const_origin

  # Set up to base of dram + 2k bytes
  ldr   up, const_dram
  add   up, up, #0x800

  # Setup the stack pointer and return stack
  ldr   rp, const_rpz
  ldr   sp, var_spz

  # tos magic value
  movw  r0, #0xbeef
  movt  r0, #0xdead
  mov   tos, r0

  # Finally set the ip to startforth
  ldr   ip, =startforth
  add   ip, ip, org

  # Go to init!
  next

.balign 4
.ltorg

#if BBB
.balign 4
_enable_vfpu_:
  # CPACR: Allow full (PL0 & PL1) access to coprocessors 10 & 11 (VFPU) 
  mrc p15, 0, r2, c1, c0, 2
  mov r3, #0xf
  orr r2, r2, r3, lsl #20
  mcr p15, 0, r2, c1, c0, 2
  isb

  # Enable the VFPU
  vmrs r2, fpexc
  mov r3, #1
  orr r2, r2, r3, lsl #30
  vmsr fpexc, r2

  bx lr

# Disable the watchdog timer
.balign 4
_disable_wdt_:
  movw r0, #0x5000
  movt r0, #0x44e3
  movw r2, #0xaaaa
wdt_wpsr_write:
  # Offset to WSPR register (watchdog timer start/stop register) 
  add r1, r0, #0x48
  str r2, [r1]
  # Offset to WWPS register (watchdog timer write posting bits register)
  add r1, r0, #0x34
wdt_wwps_poll:
  ldr r3, [r1]
  # Check if write is pending
  tst r3, #0x10
  bne wdt_wwps_poll
  movw r3, #0x5555
  teq r2, r3
  beq wdt_done
  movw r2, #0x5555
  b wdt_wpsr_write
wdt_done:
  bx lr
#endif

# Start running the Forth interpreter
startforth:
  _xt lit
  _xt 16
  _xt base
  _xt store
  _xt quit
  _xt bye

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

# Quits to command-line to interpreter
defword "quit",quit // ( -- )
  _xt rpz
  _xt rstore
  _xt stackprompt
  _xt refill
  _xt bl
  _xt word
  _xt count
  _xt number
  _xt quit

#define ORIGIN 0x80010000
#define DRAM 0x80000000

defconst "version",version,__VERSION      // Forth version
defconst "rp0",rpz,ORIGIN                 // Bottom of return stack
defconst "__enter",__enter,ORIGIN+enter   // Address of enter routine
defconst "__f_immed",__f_immed,F_IMMED    // IMMEDIATE flag value
defconst "__f_hidden",__f_hidden,F_HIDDEN // HIDDEN flag value
defconst "origin",origin,ORIGIN           // Base of dictionary image in memory
defconst "dram",dram,DRAM                 // Base of dram

defvar "here",here,ORIGIN+__here   // Next free byte in dictionary
defvar "state",state,0             // Compile/Interpreter state
defvar "base",base,10              // Current base for printing/reading numbers
defvar "sp0",spz,ORIGIN-0x400      // Bottom of data stack 

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

defcode "bye",bye // ( -- )
  b     .

# Push the value at ip on the stack and increment ip by 4
defcode "lit",lit // ( -- )
  push  tos, sp
  ldr   tos, [ip], #4
  next

# Returns address to scratch space in memory. It's a constant offset from HERE
defconst "pad",pad,__here+ORIGIN+0x100

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
defcode "?dup",questiondup // ( c ? -- c c | c )
  cmp   tos, #0
  strne tos, [sp, #-4]!
  next

# Increment value in tos
defcode "1+",oneplus // ( c -- c )
  add   tos, tos, #1
  next

# Decrement value in tos
defcode "1-",oneminus // ( c -- c )
  sub   tos, tos, #1
  next

# Add 4 to value in tos
defcode "4+",fourplus // ( c -- c )
  add   tos, tos, #4
  next

# Subtract 4 from value in tos
defcode "4-",fourminus // ( c -- c )
  sub   tos, tos, #4
  next

# Add top two values on stack
defcode "+",plus // ( c0 c1 -- c2 )
  pop   r0, sp
  add   tos, tos, r0
  next

# Subtract top two values on stack
defcode "-",minus // ( c0 c1 -- c2 )
  pop   r0, sp
  sub   tos, r0, tos
  next

# Multiply
defcode "*",star // ( c0 c1 -- c2 )
  pop   r0, sp
  mul   tos, tos, r0
  next

# Divide
defcode "/",slash // ( c0 c1 -- c2 )
  pop   r0, sp
  mov   r1, tos
  bl    _slash_
  mov   tos, r0
  next

defcode "_/_",_slash_
#if BBB
  vmov  s0, r0
  vcvt.f64.u32 d0, s0
  vmov  s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64 d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov  r0, s0
#else
  udiv  r0, r0, r1
#endif
  bx    lr

# Modulo
defcode "mod",mod // ( c0 c1 -- c2 )
  pop   r0, sp
  mov   r1, tos
  bl    _mod_
  mov   tos, r0
  next

defcode "_mod_",_mod_
#if BBB
  vmov  s0, r0
  vcvt.f64.u32 d0, s0
  vmov  s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64 d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov  r2, s0

  mls   r0, r1, r2, r0
#else
  udiv  r2, r0, r1 
  mls   r0, r1, r2, r0
#endif
  bx    lr

# divmod
defcode "/mod",slashmod // ( c0 c1 -- rem quot )
  pop   r0, sp
  mov   r1, tos
  bl    _slashmod_
  push  r0, sp
  mov   tos, r1
  next

defcode "_/mod_",_slashmod_
#if BBB
  vmov  s0, r0
  vcvt.f64.u32 d0, s0
  vmov  s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64 d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov  r2, s0

  mls   r0, r1, r2, r0
  mov   r1, r2
#else
  udiv  r2, r0, r1 
  mls   r0, r1, r2, r0
  mov   r1, r2
#endif
  bx    lr

###############################################################################
# FORTH COMPARISON OPERATORS                                                  #
###############################################################################

defcode "=",equals // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvneq tos, tos
  next

defcode "<>",notequals // ( c0 c1 -- true | false ) 
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnne tos, tos
  next

defcode "<",lessthan // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnlt tos, tos
  next

defcode ">",greaterthan // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvngt tos, tos
  next

defcode "<=",lessthanequals // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnle tos, tos
  next

defcode ">=",greaterthanequals // ( c0 c1 -- true | false )
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnge tos, tos
  next

defcode "0=",zeroequals // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvneq tos, tos
  next

defcode "0<>",zeronotequals // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnne tos, tos
  next

defcode "0<",zerolessthan // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnlt tos, tos
  next

defcode "0>",zerogreaterthan // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvngt tos, tos
  next

defcode "0<=",zerolessthanequals // ( c -- true | false )
  cmp   tos, #0
  mov   tos, #0
  mvnle tos, tos
  next

defcode "0>=",zerogreaterthanequals // ( c -- true | false )
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

defcode "+!",plusstore // ( addr -- )
  pop   r0, sp
  ldr   r1, [tos]
  add   r0, r0, r1
  str   r0, [tos]
  pop   tos, sp
  next

defcode "-!",minusstore // ( addr -- )
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

#if BBB
defconst "uart0",uart0,0x44e09000 // UART0 base address on the BeagleBone
defconst "uarthr",uarthr,0x0      // UART TX/RX holding register
defconst "uartlsr",uartlsr,0x14   // UART line status register
defconst "uartssr",uartssr,0x44   // UART supplementary status register
#else
defconst "uart0",uart0,0x1c090000 // UART0 base address
defconst "uartdr",uartdr,0x0      // UART data register
defconst "uartfr",uartfr,0x18     // UART flag register
#endif

defvar   "tib",tib,DRAM+0x100        // Location of text input buffer
defconst "tib#",tibnum,0x400         // 1k tib
defvar   ">in",toin,0x0              // Current parse area in tib

defconst "bl",bl,0x20 // space ascii character
defconst "bs",bs,0x08 // back space character
defconst "cr",cr,0x0d // carriage return
defconst "lf",lf,0x0a // line feed

defcode "emit?",emitq // ( -- true | false )
  ldr   r1, const_uart0
#if BBB
  ldr   r2, const_uartssr
  add   r1, r1, r2
  movw  r2, #0x1
#else
  ldr   r2, const_uartfr
  add   r1, r1, r2
  movw  r2, #0x20
#endif

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
#if BBB
  ldr   r2, const_uartssr
  ldr   r3, const_uarthr
  movw  r4, #0x1
#else
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  movw  r4, #0x20
#endif

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
#if BBB
  ldr   r2, const_uartlsr
  add   r1, r1, r2
  movw  r2, #0x1
#else
  ldr   r2, const_uartfr
  add   r1, r1, r2
  movw  r2, #0x10 
#endif

  mov   r0, #0
  ldr   r3, [r1]
  ands  r3, r3, r2
#if BBB
  eors  r3, r3, #1
#endif
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
#if BBB
  ldr   r2, const_uartlsr
  ldr   r3, const_uarthr
  movw  r4, #0x1
#else
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  movw  r4, #0x10
#endif

  # Wait for a character to be received
_key__LOOP:
  ldr   r5, [r1, r2]
  ands  r5, r5, r4
#if BBB
  eors  r5, r5, #1
#endif
  bne   _key__LOOP

  # Read character from RX FIFO
  ldr   r0, [r1, r3]
  bx    lr

# Reads a string of n characters from the input buffer delimited by 'char'
# places the address of the string on the stack, (the first word of the string contains
# the length of the string)
defcode "word",word // ( n char -- addr )
  pop   r0, sp
  mov   r1, tos
  bl    _word_
  mov   tos, r0
  next

defcode "_word_",_word_
  push  lr, rp
  mov   r7, r1            // r7 = delimiter
  mov   r3, r0            // String length
  ldr   r6, const_pad
  add   r6, r6, #4        // r6 = pad
  push  r6, rp            // will need this later to calculate word size

  ldr   r1, var_tib       // r1 = tib address
  ldr   r4, =var_toin     
  add   r4, r4, org       // r4 = >in pointer 
  ldr   r2, [r4]          // r2 = >in value

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
  streq r1, [rp, #8]
  beq   _accept__read_loop
 
  # Otherwise, store character in buffer and increment count
  add   r1, r1, #1
  str   r1, [rp, #8]
  strb  r0, [r7], #1
  b     _accept__read_loop

_accept__exit:
  # Emit a linefeed
  ldr   r0, const_lf
  bl    _emit_

  pop   r0, rp
  pop   r0, rp
  pop   r0, rp

  pop   lr, rp
  bx    lr

// Refills the TIB. Puts the length of the string on the stack 
defword "refill",refill // ( -- n ) 
  _xt lit
  _xt 0x0
  _xt toin
  _xt store
  _xt tib
  _xt fetch
  _xt tibnum
  _xt accept
  _xt exit

###############################################################################
# STRING PROCESSING                                                           #
###############################################################################

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

// ud2 is the result of converting the string at c-addr1 with length u1 into a number.
// each digit in c-addr1 is converted to an integer and added to ud1 after ud1 is multiplied by BASE.
// c-addr2 is the address after the string or the first non-convertible character in the string and
// u2 is the # of remaining characters in the string
defcode ">number",tonumber // ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
  mov   r2, tos // u1
  pop   r1, sp  // c-addr1
  pop   r0, sp  // ud1
  bl    _tonumber_
  push  r0, sp
  push  r1, sp
  mov   tos, r2
  next

defcode "_>number_",_tonumber_
  # Assume no leading '-'
  ldr   r3, var_base // Get BASE

_tonumber__loop:
  cmp   r2, #0
  beq   _tonumber__exit

  ldrb  r5, [r1]
  
  # Check if 'A' <= char < ('A' + (BASE-10))
  cmp   r5, #0x61
  blt   _tonumber__lowercase
  sub   r4, r3, #10
  add   r4, r4, #0x61
  cmp   r4, r5
  ble   _tonumber__lowercase
  sub   r5, r5, #0x61
  add   r5, r5, #10
  mla   r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add   r1, r1, #1           // Update string address pointer
  sub   r2, r2, #1           // Update character count
  b     _tonumber__loop

_tonumber__lowercase:
  # Check if 'a' <= char < ('a' + (BASE - 10))
  cmp   r5, #0x41
  blt   _tonumber__digit
  sub   r4, r3, #10
  add   r4, r4, #0x61
  cmp   r4, r5
  ble   _tonumber__digit
  sub   r5, r5, #0x41
  add   r5, r5, #10
  mla   r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add   r1, r1, #1           // Update string address pointer
  sub   r2, r2, #1           // Update character count
  b     _tonumber__loop

_tonumber__digit:
  # Check if '0' <= char < (0x30 + BASE | 0x3A)
  cmp   r5, #0x30
  blt   _tonumber__separator
  cmp   r3, #0xA
  movge r4, #0xA
  movlt r4, r3
  add   r4, r4, #0x30
  cmp   r4, r5
  ble   _tonumber__separator
  sub   r5, r5, #0x30
  mla   r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add   r1, r1, #1           // Update string address pointer
  sub   r2, r2, #1           // Update character count
  b     _tonumber__loop

_tonumber__separator:
  # Ignore '.' and ','
  cmp   r5, #0x2e
  addeq r1, r1, #1           // Update string address pointer
  subeq r2, r2, #1           // Update character count
  beq   _tonumber__loop
  cmp   r5, #0x2c
  addeq r1, r1, #1           // Update string address pointer
  subeq r2, r2, #1           // Update character count
  beq   _tonumber__loop

_tonumber__exit:
  bx    lr

# Converts a string into a number if possible and puts it on the stack.
# If it can't convert then nothing on stack
# Takes into account negative numbers and '0x' or '0b'
# TODO: This should be ( c-addr n -- n -1 | c-addr 0 )
defcode "number",number // ( c-addr n -- ? num )
  mov   r2, tos // n
  pop   r1, sp  // c-addr
  movw  r0, #0  // ud1
  pop   tos, sp

  # If n == 0 then nothing to convert
  cmp   r2, #0
  beq   number_exit

  # Check if '-'
  ldrb  r3, [r1]
  cmp   r3, #0x2d 
  addeq r1, r1, #1
  subeq r2, r2, #1
  moveq r3, #0x1
  streq r3, [rp, #-4]!

  # Check for leading 0
  ldrb  r4, [r1]
  cmp   r4, #0x30
  addeq r1, r1, #1
  subeq r2, r2, #1

  # Check for "x" or "X" if base = 16
  ldr   r4, var_base
  cmp   r4, #16
  bne   number_checkbinaryprefix
  ldrb  r5, [r1]
  cmp   r5, #0x58
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   number_goto__number_
  cmp   r5, #0x78
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   number_goto__number_

number_checkbinaryprefix:
  # Check for "b" or "B" if base = 2
  cmp   r4, #2
  bne   number_goto__number_
  ldrb  r5, [r1]
  cmp   r5, #0x42
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   number_goto__number_
  cmp   r5, #0x62
  addeq r1, r1, #1
  subeq r2, r2, #1
  
number_goto__number_:
  bl    _tonumber_

  # 2's complement number if negative
  ldr   r3, [rp], #4
  cmp   r3, #0x1
  mvneq r0, r0
  addeq r0, r0, #1

  # Make sure word was fully converted or else fail
  cmp   r2, #0
  streq tos, [sp, #-4]!
  moveq tos, r0

number_exit:
  next

# Prints number on stack
defcode ".",dot // ( n -- )
  mov   r0, tos
  pop   tos, sp
  bl    _dot_
  next

defcode "_._",_dot_
  push  lr, rp

  ldr   r7, var_base
  mov   r1, r7 // BASE
  movw  r6, #0 // digit count

  # Convert all the digits and push on the stack
_dot__slashmod_loop:
  bl    _slashmod_
  cmp   r1, #0   // Quotient == 0?
  str   r0, [rp, #-4]!
  add   r6, r6, #1
  mov   r0, r1
  mov   r1, r7
  bne   _dot__slashmod_loop

_dot__convert_to_char_loop:
  cmp   r6, #0 // digit count == 0?
  beq   _dot__exit
  ldr   r0, [rp], #4
  sub   r6, r6, #1
  subs  r0, r0, #10
  addmi r0, r0, #0x3a
  addpl r0, r0, #0x61
  bl    _emit_
  b     _dot__convert_to_char_loop

_dot__exit:
  pop   lr, rp
  bx    lr

// Print the Forth prompt
defword "prompt",prompt // ( -- )
  _xt lit
  _xt 0x4f
  _xt emit
  _xt lit
  _xt 0x4b
  _xt emit
  _xt lit
  _xt 0x20
  _xt emit
  _xt exit

// Print the contents of the stack before the standard prompt
defcode "stackprompt",stackprompt // ( -- )
  movw  r0, #0x28 // print a left parenthesis and space
  bl    _emit_
  movw  r0, #0x20 
  bl    _emit_

  ldr   r1, var_spz
  sub   r1, r1, #4 // skip 0xdeadbeef
  str   r1, [rp, #-4]!

  # Loop through stack contents starting from bottom of stack
stackprompt_loop:
  ldr   r1, [rp]
  sub   r1, r1, #4
  cmp   r1, sp
  ldrge r0, [r1]
  strge r1, [rp]
  blge  _dot_
  movge r0, #0x20
  blge  _emit_
  bge   stackprompt_loop

  # Print tos
  mov   r0, tos
  movw  r1, #0xbeef
  movt  r1, #0xdead
  cmp   r0, r1
  blne  _dot_
  movne r0, #0x20
  blne  _emit_

  # Print right parenthesis
  movw  r0, #0x20
  bl   _emit_
  movw  r0, #0x29
  bl    _emit_
  movw  r0, #0x20
  bl   _emit_

  # Print OK
  movw r0, #0x4f
  bl   _emit_
  movw r0, #0x4b
  bl   _emit_
  movw r0, #0x20
  bl   _emit_
  next

defvar "latest",latest,name_latest // Last entry in Forth dictionary

.balign 4
__here:

