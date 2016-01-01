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

# Store execution token of forth word in current location
.macro xt label
.int \label
.endm

.global _start
.align 2
_start:
  # Set origin = 0x10000 since this is where qemu loads the binary image
  movw  org, #0x0
  movt  org, #0x1

  # Set up the stack pointer and return stack
  ldr   r0, =docol
  add   r0, r0, org
  sub   r0, r0, #0x1000
  mov   rp, r0
  sub   r0, r0, #0x2000 // 8k return stack
  mov   sp, r0

  # tos magic value
  movw  r0, #0xbeef
  movt  r0, #0xdead
  mov   tos, r0

  # Set user pointer -> next
  ldr   up, =next
  add   up, up, org // add origin offset
  
  # Finally set the ip to coldboot
  ldr   ip, =coldboot

  # Go to init!
  bx    up

coldboot:
  xt init

.global next
.align 2
next: 
  ldr   r0, [ip, org]
  add   ip, ip, #4
  ldr   r1, [r0, org]
  add   r1, r1, org
  bx    r1



