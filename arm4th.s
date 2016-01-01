.include "common.s"

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

defcode "enter",enter
  str   ip, [rp, #-4]!
  mov   ip, lr
  next

defcode "exit",exit
  ldr   ip, [rp], #4
  next

defcode "halt",halt
  b     .

defword "init",init
  xt exit

