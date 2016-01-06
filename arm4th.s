###############################################################################
# ASSEMBLER MACROS FOR CREATING FORTH DICTIONARY ENTRIES                      #
###############################################################################

#define ORIGIN 0x80010000
#define DRAM 0x80000000

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
.balign 4
.global name_\label
name_\label:
.int link                    // link pointer
.set link,name_\label+ORIGIN // set link pointer to this word
.byte \flags                 // 1 byte for flags
.byte (12346f - 12345f)      // 1 byte for length
12345:
.ascii "\name"               // name of the word
12346:
.balign 4
.global \label
\label:                      // DTC Forth has a branch to enter as the codeword
bl enter                     // Forth words always start with enter
.endm

# Define code words
.macro defcode name,label,flags=0
.balign 4
.global name_\label
name_\label:
.int link                    // link pointer
.set link,name_\label+ORIGIN // set link pointer to this word
.byte \flags                 // 1 byte for flags
.byte (12346f - 12345f)      // 1 byte for length
12345:
.ascii "\name"               // name of the word
12346:
.balign 4
.global \label               // DTC Forth doesn't need a codeword here
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
  bl      _disable_wdt_

  # Enable the vfpu
  bl      _enable_vfpu_

  # enable the UART FIFO on the BeagleBone
  movw    r0, #0x1
  ldr     r1, const_uart0
  str     r0, [r1, #0x8]
#endif
  
  # Set origin
  movw    org, #0x0
  movt    org, #0x8001

  # Setup the stack pointer and return stack
  mov     rp, org
  sub     sp, rp, #0x400

  # tos magic value
  movw    r0, #0xbeef
  movt    r0, #0xdead
  mov     tos, r0

  # Finally set the ip to cold
  ldr     ip, =cold
  add     ip, ip, org

  # Go to init!
  next

.balign 4
.ltorg

#if BBB
.balign 4
_enable_vfpu_:
  # CPACR: Allow full (PL0 & PL1) access to coprocessors 10 & 11 (VFPU) 
  mrc     p15, 0, r2, c1, c0, 2
  mov     r3, #0xf
  orr     r2, r2, r3, lsl #20
  mcr     p15, 0, r2, c1, c0, 2
  isb

  # Enable the VFPU
  vmrs    r2, fpexc
  mov     r3, #1
  orr     r2, r2, r3, lsl #30
  vmsr    fpexc, r2

  bx      lr

# Disable the watchdog timer
.balign 4
_disable_wdt_:
  movw    r0, #0x5000
  movt    r0, #0x44e3
  movw    r2, #0xaaaa
wdt_wpsr_write:
  # Offset to WSPR register (watchdog timer start/stop register) 
  add     r1, r0, #0x48
  str     r2, [r1]
  # Offset to WWPS register (watchdog timer write posting bits register)
  add     r1, r0, #0x34
wdt_wwps_poll:
  ldr     r3, [r1]
  # Check if write is pending
  tst     r3, #0x10
  bne     wdt_wwps_poll
  movw    r3, #0x5555
  teq     r2, r3
  beq     wdt_done
  movw    r2, #0x5555
  b       wdt_wpsr_write
wdt_done:
  bx      lr
#endif

# Start running the Forth interpreter
cold:
  _xt quit
  _xt halt

###############################################################################
# CORE                                                                        #
###############################################################################

# ( val addr -- )
defcode "!",store 
  pop     r0, sp
  str     r0, [tos]
  pop     tos, sp
  next

# Multiply
# ( n0 n1 -- n2 )
defcode "*",star 
  pop     r0, sp
  mul     tos, tos, r0
  next

# Add
# ( n0 n1 -- n2 )
defcode "+",plus
  pop     r0, sp
  add     tos, tos, r0
  next

# Add n to number stored at addr 
# ( n addr -- )
defcode "+!",plus_store 
  pop     r0, sp
  ldr     r1, [tos]
  add     r0, r0, r1
  str     r0, [tos]
  pop     tos, sp
  next

# Subtract
# ( n0 n1 -- n2 )
defcode "-",minus
  pop     r0, sp
  sub     tos, r0, tos
  next

# Subtrack n to number stored in addr
# ( n addr -- )
defcode "-!",minus_store
  pop     r0, sp
  ldr     r1, [tos]
  sub     r0, r1, r0
  str     r0, [tos]
  pop     tos, sp
  next

# Display number on stack
# ( n -- )
defcode ".",dot
  mov     r0, tos
  pop     tos, sp
  bl      _dot_
  next

defcode "_._",_dot_
  push    lr, rp

  ldr     r7, var_base
  mov     r1, r7 // BASE
  movw    r6, #0 // digit count

  # Convert all the digits and push on the stack
_dot__slash_mod_loop:
  bl      _slash_mod_
  cmp     r1, #0   // Quotient == 0?
  str     r0, [rp, #-4]!
  add     r6, r6, #1
  mov     r0, r1
  mov     r1, r7
  bne     _dot__slash_mod_loop

_dot__convert_to_char_loop:
  cmp     r6, #0 // digit count == 0?
  beq     _dot__exit
  ldr     r0, [rp], #4
  sub     r6, r6, #1
  subs    r0, r0, #10
  addmi   r0, r0, #0x3a
  addpl   r0, r0, #0x61
  bl      _emit_
  b       _dot__convert_to_char_loop

_dot__exit:
  pop     lr, rp
  bx      lr

# Divide
# ( n0 n1 -- n2 )
defcode "/",slash
  pop     r0, sp
  mov     r1, tos
  bl      _slash_
  mov     tos, r0
  next

defcode "_/_",_slash_
#if BBB
  vmov    s0, r0
  vcvt.f64.u32 d0, s0
  vmov    s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64     d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov    r0, s0
#else
  udiv    r0, r0, r1
#endif
  bx      lr

# divmod
# ( n0 n1 -- rem quot )
defcode "/mod",slash_mod 
  pop     r0, sp
  mov     r1, tos
  bl      _slash_mod_
  push    r0, sp
  mov     tos, r1
  next

defcode "_/mod_",_slash_mod_
#if BBB
  vmov    s0, r0
  vcvt.f64.u32 d0, s0
  vmov    s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64     d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov    r2, s0

  mls     r0, r1, r2, r0
  mov     r1, r2
#else
  udiv    r2, r0, r1 
  mls     r0, r1, r2, r0
  mov     r1, r2
#endif
  bx      lr

# ( n -- flag )
defcode "0<",zero_less
  cmp     tos, #0
  mov     tos, #0
  mvnlt   tos, tos
  next

# ( n -- flag )
defcode "0=",zero_equals
  cmp     tos, #0
  mov     tos, #0
  mvneq   tos, tos
  next

# Increment number in tos
# ( n -- n ) 
defcode "1+",one_plus
  add     tos, tos, #1
  next

# Decrement value in tos
# ( n -- n )
defcode "1-",one_minus
  sub     tos, tos, #1
  next

# Drop 2
# ( n0 n1 -- )
defcode "2drop",two_drop
  pop     tos, sp
  pop     tos, sp
  next

# Duplicate top two elements
# ( n0 n1 -- n0 n1 n0 n1 )
defcode "2dup",two_dup
  ldr     r0, [sp]
  push    tos, sp
  push    r0, sp
  next

# Push the 2nd & 3rd items on the stack to the top of the stack
# ( n0 n1 n2 -- n0 n1 n2 n0 n1 )
defcode "2over",two_over
  ldr     r0, [sp]
  ldr     r1, [sp, #4]
  push    tos, sp
  push    r1, sp
  mov     tos, r0
  next

# Swap first two elements with next two
# ( n0 n1 n2 n3 -- n2 n3 n0 n1 )
defcode "2swap",twoswap 
  pop     r0, sp
  pop     r1, sp
  pop     r2, sp
  push    r0, sp
  push    tos, sp
  push    r2, sp
  mov     tos, r2
  next

# ( n0 n1 -- flag )
defcode "<",less_than 
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvnlt   tos, tos
  next

# ( n0 n1 -- flag )
defcode "=",equals 
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvneq   tos, tos
  next

# ( n0 n1 -- flag ) 
defcode ">",greater_than 
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvngt   tos, tos
  next

# Get the address to the word's parameter list
# ( addr1 -- addr2 )
defcode ">body",to_body // ( addr1 -- addr2 )
  mov     r0, tos
  bl      _to_body_
  mov     tos, r0
  next

defcode "_>body_",_to_body_
  ldrb    r1, [r0, #5]
  add     r0, r0, #6
  add     r0, r0, r1 // skip header
  ands    r7, r0, #0x3 // Round to next 4-byte boundary
  mvnne   r7, #0x3
  andne   r0, r0, r7
  addne   r0, r0, #0x4
  bx      lr

# Current parse area in TIB
# ( -- a-addr )
defvar ">in",to_in,0x0

# ud2 is the result of converting the string at c-addr1 with length u1 into a number.
# each digit in c-addr1 is converted to an integer and added to ud1 after ud1 is multiplied by BASE.
# c-addr2 is the address after the string or the first non-convertible character in the string and
# u2 is the # of remaining characters in the string
# ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 ) 
defcode ">number",to_number 
  mov     r2, tos // u1
  pop     r1, sp  // c-addr1
  pop     r0, sp  // ud1
  bl      _to_number_
  push    r0, sp
  push    r1, sp
  mov     tos, r2
  next

defcode "_>number_",_to_number_
  # Assume no leading '-'
  ldr     r3, var_base // Get BASE

_to_number__loop:
  cmp     r2, #0
  beq     _to_number__exit

  ldrb    r5, [r1]
  
  # Check if 'A' <= char < ('A' + (BASE-10))
  cmp     r5, #0x61
  blt     _to_number__lowercase
  sub     r4, r3, #10
  add     r4, r4, #0x61
  cmp     r4, r5
  ble     _to_number__lowercase
  sub     r5, r5, #0x61
  add     r5, r5, #10
  mla     r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add     r1, r1, #1           // Update string address pointer
  sub     r2, r2, #1           // Update character count
  b       _to_number__loop

_to_number__lowercase:
  # Check if 'a' <= char < ('a' + (BASE - 10))
  cmp     r5, #0x41
  blt     _to_number__digit
  sub     r4, r3, #10
  add     r4, r4, #0x61
  cmp     r4, r5
  ble     _to_number__digit
  sub     r5, r5, #0x41
  add     r5, r5, #10
  mla     r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add     r1, r1, #1           // Update string address pointer
  sub     r2, r2, #1           // Update character count
  b       _to_number__loop

_to_number__digit:
  # Check if '0' <= char < (0x30 + BASE | 0x3A)
  cmp     r5, #0x30
  blt     _to_number__separator
  cmp     r3, #0xA
  movge   r4, #0xA
  movlt   r4, r3
  add     r4, r4, #0x30
  cmp     r4, r5
  ble     _to_number__separator
  sub     r5, r5, #0x30
  mla     r0, r0, r3, r5       // Multiply r0 with BASE and add the converted digit
  add     r1, r1, #1           // Update string address pointer
  sub     r2, r2, #1           // Update character count
  b       _to_number__loop

_to_number__separator:
  # Ignore '.' and ','
  cmp     r5, #0x2e
  addeq   r1, r1, #1           // Update string address pointer
  subeq   r2, r2, #1           // Update character count
  beq     _to_number__loop
  cmp     r5, #0x2c
  addeq   r1, r1, #1           // Update string address pointer
  subeq   r2, r2, #1           // Update character count
  beq     _to_number__loop

_to_number__exit:
  bx      lr

# ( x -- ) ( R: -- x )
defcode ">r",to_r 
  push    tos, rp
  pop     tos, sp
  next

# Duplicate top of stack if not zero
# ( x -- 0 | x x )
defcode "?dup",question_dup 
  cmp     tos, #0
  strne   tos, [sp, #-4]!
  next

# ( addr -- val )
defcode "@",fetch 
  mov     r0, tos
  ldr     tos, [r0]
  next

# Read in at most count chars from input to addr, stopping if a CR/LF is read
# Places the length of the string on the stack
# ( c-addr n0 -- n1 )
defcode "accept",accept
  pop     r1, sp  // addr
  mov     r0, tos // count
  bl      _accept_
  mov     tos, r0
  next

defcode "_accept_",_accept_
  push    lr, rp

  mov     r7, r1 // addr
  mov     r6, r0 // max count

  movw    r0, #0
  push    r0, rp       // character count
  movw    r0, #0x08    // backspace
  push    r0, rp
  movw    r0, #0x0d    // carriage return
  push    r0, rp

_accept__read_loop:
  ldr     r1, [rp, #8]
  cmp     r1, r6       // Reached max count?
  beq     _accept__exit

  bl      _key_
  bl      _emit_       // echo character
  
  ldr     r1, [rp, #8] // character count
  
  ldr     r2, [rp]
  cmp     r2, r0       // carriage return?
  beq     _accept__exit

  ldr     r2, [rp, #4]
  cmp     r2, r0       // backspace?
  subeq   r7, r7, #1
  subeq   r1, r1, #1
  streq   r1, [rp, #8]
  beq     _accept__read_loop
 
  # Otherwise, store character in buffer and increment count
  add     r1, r1, #1
  str     r1, [rp, #8]
  strb    r0, [r7], #1
  b       _accept__read_loop

_accept__exit:
  # Emit a linefeed
  movw    r0, #0x0a
  bl      _emit_

  pop     r0, rp
  pop     r0, rp
  pop     r0, rp

  pop     lr, rp
  bx      lr

# Align the HERE pointer
# ( -- )
defword "align",align
  _xt here
  _xt dup
  _xt aligned
  _xt swap
  _xt store
  _xt exit

# Align addr to 4-byte boundary
# ( addr -- a-addr )
defcode "aligned",aligned
  ands    r0, tos, #3
  mvnne   r0, #3
  andne   tos, tos, r0
  addne   tos, tos, #4
  next

# ( n0 n1 -- n2 )
defcode "and",and
  pop     r0, sp
  and     tos, r0, tos
  next

# Current base for displaying/reading numbers
# ( -- a-addr )
defvar "base",base,10

# ASCII space character
# ( -- char )
defconst "bl",bl,0x20

# Store byte
# ( char c-addr -- )
defcode "c!",c_store
  pop     r0, sp
  strb    r0, [tos]
  pop     tos, sp
  next

# Load byte
# ( c-addr -- char )
defcode "c@",c_fetch
  mov     r0, tos
  ldrb    tos, [r0]
  next

# Get the ASCII character of the first character in name
# ( "<spaces>name" -- char )
defcode "char",char
  bl      _char_
  push    tos, sp
  mov     tos, r0
  next

defcode "_char_",_char_
  ldr     r7, const_bl       // r7 = delimiter
  ldr     r1, var__tib_        // r1 = tib address
  ldr     r2, var_to_in      // r2 = >in value
  ldr     r3, var_number_tib // TIB string length

  # Skip leading delimiters
_char__skip_loop:
  # Check if end of input string
  cmp     r2, r3
  bge     _char__exit

  ldrb    r0, [r1, r2]
  add     r2, r2, #1

  # Check if delimiter and skip
  cmp     r0, r7
  beq     _char__skip_loop

_char__exit:
  bx      lr

# Leave the address and length of string beginning at addr1 on the stack
# ( c-addr0 -- c-addr1 u ) 
defcode "count",count // ( addr1 -- addr2 n )
  mov     r0, tos
  bl      _count_
  mov     tos, r1
  push    r0, sp
  next

defcode "_count_",_count_
  ldrb    r1, [r0]    // String length
  add     r0, r0, #1  // Actual string starting address
  bx      lr

# Output a carriage return
# ( -- )
defcode "cr",cr 
  bl      _cr_
  next

defcode "_cr_",_cr_
  push    lr, rp
  movw    r0, #0x20
  bl      _emit_
  pop     lr, rp
  next

# Change the base to decimal
# ( -- )
defword "decimal",decimal
  _xt lit
  _xt 10
  _xt base
  _xt store
  _xt exit

# The number of items on the data stack before n was placed on the stack
# ( -- n )
defcode "depth",depth
  ldr     r0, var_spz
  sub     r0, r0, sp
  next

# Drop top of stack
# ( x -- )
defcode "drop",drop
  pop     tos, sp
  next

# Duplicate tos 
# ( x -- x x )
defcode "dup",dup
  push    tos, sp
  next

# Print character on stack to UART
# ( c -- )
defcode "emit",emit
  mov     r0, tos
  pop     tos, sp
  bl      _emit_
  next

defcode "_emit_",_emit_
#if BBB
  movw    r1, #0x9000
  movt    r1, #0x44e0
  mov     r2, #0x44 // UART supplementary status register offset
  mov     r3, #0x0  // UART holding register offset
  movw    r4, #0x1
#else
  movw    r1, #0x0
  movt    r1, #0x1c09
  mov     r2, #0x18 // UART flag register offset
  mov     r3, #0x0  // UART data register offset
  movw    r4, #0x20
#endif

  # Wait for TX FIFO to be not full
_emit__LOOP:
  ldr     r5, [r1, r2]
  ands    r5, r5, r4
  bne     _emit__LOOP
  
  # Put character in TX FIFO
  str     r0, [r1, r3]
  bx      lr

# Sets c-addr and u as the TIB and TIB size, sets >IN to 0 and
# interprets the string
# ( c-addr u -- )
# TODO
defcode "evaluate",evaluate
parseline_loop:
  bl    _interpret_
  ldr   r0, var_number_tib
  ldr   r1, var_to_in
  cmp   r1, r0 // >in < n?
  blt   parseline_loop
  next

# Jump to the Forth Word execution token provided on the stack
# TODO: SHOULD I 4- IP?
# ( xt -- )
defcode "execute",execute
  sub     ip, ip, #4
  mov     r0, tos
  pop     tos, sp
  blx     r0
  next

# Exit a Forth word
# ( -- )
defcode "exit",exit
  pop     ip, rp
  next

# Fill starting from c-addr with u char's
# ( c-addr u char -- )
defcode "fill",fill
  mov     r2, tos
  pop     r1, sp
  pop     r0, sp
  pop     tos, sp
  bl      _fill_
  next

defcode "_fill_",_fill_
_fill__loop:
  cmp     r1, #0
  subne   r1, r1, #1
  #strbne  r2, [r0, r1]
  bne     _fill__loop
  bx      lr

# Puts c-addr and false on the stack if word could not be found.
# If the word was found and it is an immediate word then place the execution
# token and 1 on the stack otherwise put -1 on the stack.
# ( c-addr -- c-addr 0 | xt 1 | xt -1 )
defcode "find",find 
  mov     r0, tos
  bl      _find_
  push    r0, sp
  mov     tos, r1
  next

defcode "_find_",_find_
  push    lr, rp

  bl      _count_
  cmp     r1, #0
  moveq   r7, #0
  beq     _find__done // String length is zero!

  ldr     r2, var_latest
  mov     r7, #0 // Found or not found

_find__loop:
  cmp     r2, #0
  beq     _find__done // Stop if 0 link pointer 
  ldrb    r4, [r2, #5]
  cmp     r4, r1 // Check if name lengths are the same
  ldrne   r2, [r2]
  bne     _find__loop

  # Attempt to match the strings
  add     r3, r2, #6

_find__match:
  cmp     r4, #0
  movle   r7, #1  // Found it!
  ble     _find__done
  sub     r4, r4, #1
  ldrb    r5, [r3, r4]
  ldrb    r6, [r0, r4]
  cmp     r5, r6
  beq     _find__match
  ldrne   r2, [r2]
  bne     _find__loop // If strings don't match, keep searching dictionary

_find__done:
  cmp     r7, #0
  moveq   r1, #0
  subeq   r0, r0, #1
  beq     _find__exit

  mov     r0, r2
  bl      _to_body_
  
  mov     r1, #-1
  ldr     r7, [r2, #4] // Check if immediate
  ands    r7, r7, #0x80
  movne   r1, #1 // It is immediate

_find__exit:
  pop     lr, rp
  bx      lr

# addr is the pointer to the next free address in memory
# ( -- addr )
defword "here",here
  _xt _here_
  _xt fetch
  _xt exit

# Next free byte in dictionary
defvar "_here_",_here_,ORIGIN+__here   

# Bitwise not of n0
# ( n0 -- n1 )
defcode "invert",invert
  mvn     tos, tos
  next

# Read character from UART to stack
# ( -- char )
defcode "key",key 
  bl      _key_
  push    tos, sp
  mov     tos, r0
  next

defcode "_key_",_key_
#if BBB
  movw    r1, #0x9000
  movt    r1, #0x44e0
  mov     r2, #0x14 // UART line status register offset 
  mov     r3, #0x0  // UART holding register offset
  movw    r4, #0x1
#else
  movw    r1, #0x0
  movt    r1, #0x1c09
  mov     r2, #0x18 // UART flag register offset 
  mov     r3, #0x0  // UART data register offset
  movw    r4, #0x10
#endif

  # Wait for a character to be received
_key__LOOP:
  ldr     r5, [r1, r2]
  ands    r5, r5, r4
#if BBB
  eors    r5, r5, #1
#endif
  bne     _key__LOOP

  # Read character from RX FIFO
  ldr     r0, [r1, r3]
  bx      lr

# Modulo
# ( n0 n1 -- n2 )
defcode "mod",mod 
  pop     r0, sp
  mov     r1, tos
  bl      _mod_
  mov     tos, r0
  next

defcode "_mod_",_mod_
#if BBB
  vmov    s0, r0
  vcvt.f64.u32 d0, s0
  vmov    s2, r1
  vcvt.f64.u32 d1, s2

  vdiv.f64     d0, d0, d1
  vcvt.u32.f64 s0, d0

  vmov    r2, s0

  mls     r0, r1, r2, r0
#else
  udiv    r2, r0, r1 
  mls     r0, r1, r2, r0
#endif
  bx      lr

# Arithmetic inverse of n0
# ( n0 -- n1 )
defcode "negate",negate
  mvn     tos, tos
  add     tos, tos, #1 // Two's complement
  next

# Drop second item on stack
# ( n0 n1 -- n1 )
defcode "nip",nip
  pop     r0, sp
  next

# ( n0 n1 -- n2 )
defcode "or",or
  pop     r0, sp
  orr     tos, r0, tos
  next

# Place second element on tos
# ( n0 n1 -- n0 n1 n0 )
defcode "over",over
  push    tos, sp
  ldr     tos, [sp, #4]
  next

# Quits to command-line to interpreter
# TODO
# ( -- )
defword "quit",quit
  _xt rpz
  _xt rpstore
  _xt prompt
  _xt pad
  _xt lit
  _xt 0x100
  _xt plus
  _xt _tib_
  _xt store
  _xt refill
  _xt drop
  _xt evaluate
  _xt quit

# ( -- x ) ( R: x -- )
defcode "r>",r_from
  push    tos, sp
  pop     tos, rp
  next

# ( -- x ) ( R: x -- x )
defcode "r@",r_fetch
  push    tos, sp
  ldr     tos, [rp]
  next

# Rotate the first three elements on the stack
# ( n0 n1 n2 -- n1 n2 n0 )
defcode "rot",rot
  pop     r0, sp
  pop     r1, sp
  push    tos, sp
  push    r1, sp
  mov     tos, r0
  next

# Current state: interpret (0) or compile (1)
# ( -- a-addr ) 
defvar "state",state,0

# Swap tos with next element on stack
# ( n0 n1 -- n1 n0 )
defcode "swap",swap
  mov     r0, tos
  pop     tos, sp
  push    r0, sp
  next

defword "tib",tib
  _xt _tib_
  _xt fetch
  _xt exit

# Location of text input buffer
defvar "_tib_",_tib_,0x0

# Tuck the first item under the second item on the stack
# ( x0 x1 -- x1 x0 x1 )
defcode "tuck",tuck
  pop     r0, sp
  push    tos, sp
  push    r0, sp
  next

# Reads a string of #tib characters from the input buffer delimited by 'char'
# places the address of the string on the stack, (the first word of the string contains
# the length of the string)
# TODO: SHOULD NOT USE PAD
# ( char "<char>cccc<char>" -- c-addr )
defcode "word",word
  mov     r0, tos
  bl      _word_
  mov     tos, r0
  next

defcode "_word_",_word_
  push    lr, rp
  mov     r7, r0             // r7 = delimiter

  bl      _pad_
  mov     r6, r0
  add     r6, r6, #1         // r6 = pad
  push    r6, rp             // will need this later to calculate word size

  ldr     r1, var__tib_      // r1 = tib address
  ldr     r2, var_to_in      // r2 = >in value
  ldr     r3, var_number_tib // TIB string length

  # Skip leading delimiters
_word__skip_loop:
  # Check if end of TIB and exit with 0 length word
  cmp     r2, r3
  bge     _word__exit

  ldrb    r0, [r1, r2]
  add     r2, r2, #1
  
  # Check if delimiter and skip
  cmp     r0, r7
  beq     _word__skip_loop
  
  # Start reading characters into pad+1 
_word__read_loop:
  strb    r0, [r6], #1

  # Check if end of TIB and exit
  cmp     r2, r3
  bge     _word__exit

  ldrb    r0, [r1, r2]
  add     r2, r2, #1
  cmp     r0, r7
  bne     _word__read_loop

  # Calculate length and store it
_word__exit:
  pop     r0, rp
  sub     r6, r6, r0
  strb    r6, [r0, #-1]!

  # Update >in
  str     r2, var_to_in

  pop     lr, rp
  bx      lr

# ( n0 -- n1 )
defcode "xor",xor 
  pop     r0, sp
  eor     tos, r0, tos
  next

###############################################################################
# CORE EXTENSIONS                                                             #
###############################################################################

# Current number of chars in TIB
# ( -- n )
defvar "#tib",number_tib,0x0 

# ( n -- true | false )
defcode "0<>",zero_not_equals
  cmp     tos, #0
  mov     tos, #0
  mvnne   tos, tos
  next

# ( n -- true | false )
defcode "0>",zero_greater
  cmp     tos, #0
  mov     tos, #0
  mvngt   tos, tos
  next

# ( n0 n1 -- flag )
defcode "<>",not_equals 
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvnne   tos, tos
  next

# Changes the base to hex
# ( -- )
defword "hex",hex
  _xt lit
  _xt 16
  _xt base
  _xt store
  _xt exit

# Returns address to scratch space in memory. It's a constant offset from HERE
# ( -- addr )
defcode "pad",pad
  bl      _pad_
  push    tos, sp
  mov     tos, r0
  next

defcode "_pad_",_pad_
  movw    r1, #0x0
  movt    r1, #0x0100
  ldr     r0, var__here_
  add     r0, r0, r1
  bx      lr

# Refills the TIB
# ( -- flag )
defword "refill",refill  
  _xt lit
  _xt 0x0
  _xt to_in
  _xt store
  _xt tib
  _xt lit
  _xt 0x400
  _xt accept
  _xt number_tib
  _xt store
  _xt lit
  _xt 0xffffffff
  _xt exit

###############################################################################
# STRING                                                                      #
###############################################################################

# Block byte copy
# ( c-addr0 c-addr1 u -- )
defcode "cmove",cmove
  pop     r0, sp // destination
  pop     r1, sp // source
  mov     r2, tos // length
  pop     tos, sp
  bl      _cmove_
  next

defcode "_cmove_",_cmove_
_cmove__LOOP:
  ldrb    r3, [r1], #1
  strb    r3, [r0], #1
  subs    r2, r2, #1
  bne     _cmove__LOOP
  bx      lr

###############################################################################
# PRIVATE EXTENSIONS                                                          #
###############################################################################

# Rotate the other way
# ( n0 n1 n2 -- n2 n0 n1 )
defcode "-rot",minus_rot
  pop     r0, sp
  pop     r1, sp
  push    r0, sp
  push    tos, sp
  mov     tos, r1
  next

# ( n0 n1 -- flag )
defcode "<=",less_equals
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvnle   tos, tos
  next

# ( n0 n1 -- flag )
defcode ">=",greater_equals
  pop     r0, sp
  cmp     r0, tos
  mov     tos, #0
  mvnge   tos, tos
  next

# ( n0 n1 -- flag )
defcode "0<=",zero_less_equals
  cmp     tos, #0
  mov     tos, #0
  mvnle   tos, tos
  next

# ( n0 n1 -- flag )
defcode "0>=",zero_greater_equals
  cmp     tos, #0
  mov     tos, #0
  mvnge   tos, tos
  next
# ( flag -- )
defcode "?branch",question_branch
  mov     r0, tos
  pop     tos, sp
  cmp     r0, #0
  ldrne   r0, [ip]
  addne   ip, ip, r0, lsl #2  // jump interpreter
  addeq   ip, ip, #4          // otherwise skip next xt
  next

# Converts a string into a number if possible and puts it on the stack.
# If it can't convert then nothing on stack
# Takes into account negative numbers and '0x' or '0b'
# ( c-addr -- n true | c-addr false )
defcode "?number",question_number
  mov   r0, tos // c-addr
  bl    _question_number_
  push  r0, sp
  mov   tos, r1
  next

defcode "_?number_",_question_number_
  push  lr, rp

  bl    _count_
  mov   r2, r1  // n
  mov   r1, r0  // c-addr
  movw  r0, #0  // u

  # If n == 0 then nothing to convert
  cmp   r2, #0
  moveq r0, r1
  moveq r1, #0
  beq   question_number_exit
  push  r1, rp

  # Check if '-'
  ldrb  r3, [r1]
  cmp   r3, #0x2d 
  addeq r1, r1, #1
  subeq r2, r2, #1
  movne r3, #0x0
  moveq r3, #0x1
  push  r3, rp

  # Check for leading 0
  ldrb  r4, [r1]
  cmp   r4, #0x30
  addeq r1, r1, #1
  subeq r2, r2, #1

  # Check for "x" or "X" if base = 16
  ldr   r4, var_base
  cmp   r4, #16
  bne   question_number_checkbinaryprefix
  ldrb  r5, [r1]
  cmp   r5, #0x58
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   question_number__to_number_
  cmp   r5, #0x78
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   question_number__to_number_

question_number_checkbinaryprefix:
  # Check for "b" or "B" if base = 2
  cmp   r4, #2
  bne   question_number__to_number_
  ldrb  r5, [r1]
  cmp   r5, #0x42
  addeq r1, r1, #1
  subeq r2, r2, #1
  beq   question_number__to_number_
  cmp   r5, #0x62
  addeq r1, r1, #1
  subeq r2, r2, #1
  
question_number__to_number_:
  bl    _to_number_

  # 2's complement number if negative
  pop   r3, rp
  cmp   r3, #0x1
  mvneq r0, r0
  addeq r0, r0, #1
 
  # Check if word was fully converted to a number
  pop   r3, rp
  mov   r1, #0
  cmp   r2, #0
  mvneq r1, r1 // r0 = n, r1 = true
  subne r3, r3, #1
  movne r0, r3 // r0 = c-addr, r1 = false

question_number_exit:
  pop   lr, rp
  bx    lr

# Prologue to every high-level Forth word
# ( -- ) ( R: -- addr )
defcode "enter",enter
  push    ip, rp
  mov     ip, lr
  next

# halt
# ( -- )
defcode "halt",halt
  b       .

# TODO
# ( c-addr u -- )
defcode "interpret",interpret
  bl    _interpret_
  next

defcode "_interpret_",_interpret_
  push  lr, rp

  ldr   r0, const_bl
  bl    _word_
  bl    _find_
  cmp   r1, #0
  strne tos, [sp, #-4]!
  movne tos, r0
  blne  execute
  
  bl    _question_number_
  cmp   r1, #0
  strne tos, [sp, #-4]!
  movne tos, r0
  
  pop   lr, rp
  bx    lr

# Push the value at ip on the stack and increment ip by 4
# ( -- n )
defcode "lit",lit 
  push    tos, sp
  ldr     tos, [ip], #4
  next

# Print the contents of the stack before the standard prompt
# ( -- )
defcode "prompt",prompt
  movw  r0, #0x28 // print a left parenthesis and space
  bl    _emit_
  movw  r0, #0x20 
  bl    _emit_

  ldr   r1, var_spz
  sub   r1, r1, #4 // skip 0xdeadbeef
  str   r1, [rp, #-4]!

  # Loop through stack contents starting from bottom of stack
prompt_loop:
  ldr   r1, [rp]
  sub   r1, r1, #4
  cmp   r1, sp
  ldrge r0, [r1]
  strge r1, [rp]
  blge  _dot_
  movge r0, #0x20
  blge  _emit_
  bge   prompt_loop

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
  bl    _emit_
  movw  r0, #0x29
  bl    _emit_
  movw  r0, #0x20
  bl    _emit_

  # Print OK
  movw  r0, #0x6f
  bl    _emit_
  movw  r0, #0x6b
  bl    _emit_
  movw  r0, #0x20
  bl    _emit_
  next

# Bottom of return stack
# ( -- addr )
defconst "rp0",rpz,ORIGIN

# Replaces rp with n
# ( n -- )
defcode "rp!",rpstore
  mov     rp, tos
  pop     tos, sp
  next

# Bottom of data stack
defvar "sp0",spz,ORIGIN-0x400

# Last entry in Forth dictionary
defvar "latest",latest,name_latest+ORIGIN

.balign 4
__here:
