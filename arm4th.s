.include "common.s"

defcode "halt",halt
  b     .

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

# Enter a Forth word
defcode "enter",enter
  push  ip, rp
  mov   ip, lr
  next

# Exit a Forth word
defcode "exit",exit
  pop   ip, rp
  next

# Push the value at ip on the stack and increment ip by 4
defcode "lit",lit
  push  tos, sp
  ldr   tos, [ip], #4
  next
# Drop top of stack
defcode "drop",drop
  pop   tos, sp
  next

# Swap tos with next element on stack
defcode "swap",swap
  mov   r0, tos
  pop   tos, sp
  push  r0, sp
  next

# Duplicate tos
defcode "dup",dup
  push  tos, sp
  next

# Place second element on tos
defcode "over",over
  push  tos, sp
  ldr   tos, [sp, #4]
  next

# Rotate the first three elements on the stack
defcode "rot",rot
  pop   r0, sp
  pop   r1, sp
  push  tos, sp
  push  r1, sp
  mov   tos, r0
  next

# Rotate the other way
defcode "-rot",nrot
  pop   r0, sp
  pop   r1, sp
  push  r0, sp
  push  tos, sp
  mov   tos, r1
  next

# Drop 2
defcode "2drop",twodrop
  pop   tos, sp
  pop   tos, sp
  next

# Duplicate top two elements
defcode "2dup",twodup
  ldr   r0, [sp]
  push  tos, sp
  push  r0, sp
  next

# Swap first two elements with next two
defcode "2swap",twoswap
  pop   r0, sp
  pop   r1, sp
  pop   r2, sp
  push  r0, sp
  push  tos, sp
  push  r2, sp
  mov   tos, r2
  next

# Duplicate top of stack if not zero
defcode "?dup",qdup
  cmp   tos, #0
  strne tos, [sp, #-4]!
  next

# Increment value in tos
defcode "1+",incr
  add   tos, tos, #1
  next

# Decrement value in tos
defcode "1-",decr
  sub   tos, tos, #1
  next

# Add 4 to value in tos
defcode "4+",incr4
  add   tos, tos, #4
  next

# Subtract 4 from value in tos
defcode "4-",decr4
  sub   tos, tos, #4
  next

# Add top two values on stack
defcode "+",add
  pop   r0, sp
  add   tos, tos, r0
  next

# Subtract top two values on stack
defcode "-",sub
  pop   r0, sp
  sub   tos, r0, tos
  next

# Multiply
defcode "*",mul
  pop   r0, sp
  mul   tos, tos, r0
  next

# Divide
defcode "/",div
  pop   r0, sp
  udiv  tos, r0, tos
  next

# Modulo
defcode "%",mod
  pop   r0, sp
  mov   r1, tos
  udiv  tos, r0, tos 
  mul   tos, tos, r1
  sub   tos, r0, tos
  next

##### FORTH COMPARISON OPERATORS
defcode "=",equ
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvneq tos, tos
  next

defcode "<>",nequ
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnne tos, tos
  next

defcode "<",lt
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnlt tos, tos
  next

defcode ">",gt
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvngt tos, tos
  next

defcode "<=",le
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnle tos, tos
  next

defcode ">=",ge
  pop   r0, sp
  cmp   r0, tos
  mov   tos, #0
  mvnge tos, tos
  next

defcode "0=",zequ
  cmp   tos, #0
  mov   tos, #0
  mvneq tos, tos
  next

defcode "0<>",znequ
  cmp   tos, #0
  mov   tos, #0
  mvnne tos, tos
  next

defcode "0<",zlt
  cmp   tos, #0
  mov   tos, #0
  mvnlt tos, tos
  next

defcode "0>",zgt
  cmp   tos, #0
  mov   tos, #0
  mvngt tos, tos
  next

defcode "0<=",zle
  cmp   tos, #0
  mov   tos, #0
  mvnle tos, tos
  next

defcode "0>=",zge
  cmp   tos, #0
  mov   tos, #0
  mvnge tos, tos
  next

##### FORTH BITWISE OPERATORS
defcode "and",and
  pop   r0, sp
  and   tos, r0, tos
  next

defcode "or",or
  pop   r0, sp
  orr   tos, r0, tos
  next

defcode "xor",xor
  pop   r0, sp
  eor   tos, r0, tos
  next

##### FORTH MEMORY OPERATIONS
defcode "!",store
  pop   r0, sp
  str   r0, [tos]
  pop   tos, sp
  next

defcode "@",fetch
  mov   r0, tos
  ldr   tos, [r0]
  next

defcode "+!",addstore
  pop   r0, sp
  ldr   r1, [tos]
  add   r0, r0, r1
  str   r0, [tos]
  pop   tos, sp
  next

defcode "-!",substore
  pop   r0, sp
  ldr   r1, [tos]
  sub   r0, r1, r0
  str   r0, [tos]
  pop   tos, sp
  next

# Store/Load Bytes
defcode "c!",storebyte
  pop   r0, sp
  strb  r0, [tos]
  pop   tos, sp
  next

defcode "c@",fetchbyte
  mov   r0, tos
  ldrb  tos, [r0]
  next

# Fetch byte from source and store byte to destination
defcode "c@c!",ccopy
  pop   r0, sp
  ldrb  r1, [r0]
  strb  r1, [tos]
  pop   tos, sp
  next

# Block byte copy
defcode "cmove",cmove
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

##### RETURN STACK MANIPULATION
defcode ">r",tor
  push  tos, rp
  pop   tos, sp
  next

defcode "r>",fromr
  push  tos, sp
  pop   tos, rp
  next

defcode "r@",rfetch
  push  tos, sp
  ldr   tos, [rp]
  next

defcode "r!",rstore
  str   tos, [rp]
  pop   tos, sp
  next

##### STACK MANIPULATION
defcode "sp@",spfetch
  push  tos, sp
  mov   tos, sp
  next

defcode "sp!",spstore
  mov   r0, tos
  pop   tos, sp
  mov   sp, r0
  next

##### INPUT/OUTPUT
defconst "uart0",uart0,0x1c090000 // UART0 base address
defconst "uartdr",uartdr,0x0      // UART data register
defconst "uartfr",uartfr,0x18     // UART flag register

# Relevant bits in the UARTFR register
defconst "uartfr_busy",uartfr_busy,0x8  // UART busy, set when TX FIFO is non-empty
defconst "uartfr_rxfe",uartfr_rxfe,0x10 // RX FIFO is empty
defconst "uartfr_txff",uartfr_txff,0x20 // TX FIFO is full
defconst "uartfr_rxff",uartfr_rxff,0x40 // RX FIFO is full
defconst "uartfr_txfe",uartfr_txfe,0x80 // TX FIFO is empty

defcode "_emit_",_emit_
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  ldr   r4, const_uartfr_txff

  # Wait for TX FIFO to be not full
_emit__LOOP:
  ldr   r5, [r1, r2]
  ands  r5, r5, r4
  bne   _emit__LOOP
  
  # Put character in TX FIFO
  str   r0, [r1, r3]
  bx    lr

# Print character on stack to UART
defcode "emit",emit
  mov   r0, tos
  pop   tos, sp
  bl    _emit_
  next

defcode "_key_",_key_
  ldr   r1, const_uart0
  ldr   r2, const_uartfr
  ldr   r3, const_uartdr
  ldr   r4, const_uartfr_rxfe

  # Wait for a character to be received
_key__LOOP:
  ldr   r5, [r1, r2]
  ands  r5, r5, r4
  bne   _key__LOOP

  # Read character from RX FIFO
  ldr   r0, [r1, r3]
  bx    lr

# Read character from UART to stack
defcode "key",key
  bl    _key_
  push  tos, sp
  mov   tos, r0
  next

##### STANDARD FORTH VARIABLES & CONSTANTS
defvar "latest",latest,name_init  // Last entry in Forth dictionary
defvar "here",here                // Next free byte in dictionary
defvar "state",state              // Compile/Interpreter state
defvar "base",base,10             // Current base for printing/reading numbers

defconst "version",version,__VERSION      // Forth version
defconst "__enter",__enter,enter          // Address of enter routine
defconst "__f_immed",__f_immed,F_IMMED    // IMMEDIATE flag value
defconst "__f_hidden",__f_hidden,F_HIDDEN // HIDDEN flag value

# Test sequence!
defword "init",init
  _xt key
  _xt emit
  _xt key
  _xt emit
  _xt key
  _xt emit
  _xt key
  _xt emit
  _xt key
  _xt emit

  _xt exit

