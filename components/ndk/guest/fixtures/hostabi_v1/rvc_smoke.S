/* rvc_smoke.S - RV32C Compressed Instruction Smoke Test */
/* Executes explicit compressed instructions and returns */

.section .text.rvc_smoke, "ax"
.global rvc_smoke_test
.type rvc_smoke_test, @function

/* Enable compressed instructions for this function */
.option rvc

rvc_smoke_test:
    /* c.addi: add immediate (compressed) */
    c.addi a0, 5
    
    /* c.li: load immediate (compressed) */
    c.li a1, 10
    
    /* c.add: compressed register-register add */
    c.add a0, a1         /* a0 = a0 + a1 = 15 */
    
    /* c.slli: compressed shift left logical immediate */
    c.slli a0, 2         /* a0 = 15 << 2 = 60 */
    
    /* c.swsp: store word to stack pointer (compressed) */
    c.addi sp, -16       /* Allocate stack space */
    c.swsp a0, 8(sp)     /* Store a0 to sp+8 */
    
    /* c.lwsp: load word from stack pointer (compressed) */
    c.lwsp a2, 8(sp)     /* Load from sp+8 to a2 */
    c.addi sp, 16        /* Deallocate stack space */
    
    /* c.andi: compressed AND immediate */
    c.andi a0, 31        /* a0 = 60 & 31 = 28 */
    
    /* c.mv: compressed move (pseudo-op for c.add rd, x0, rs) */
    c.mv a2, a0          /* a2 = a0 */
    
    /* Prepare for conditional branch test */
    c.li a3, 0           /* Set a3 to 0 */
    
    /* c.beqz: branch if equal to zero (compressed) */
    c.beqz a3, .Lbeqz_taken
    c.li a0, -1          /* Should be skipped */
    c.j .Lbeqz_done
.Lbeqz_taken:
    c.li a0, 12          /* This should execute */
.Lbeqz_done:
    
    /* c.bnez: branch if not equal to zero (compressed) */
    c.li a3, 1           /* Set a3 to 1 */
    c.bnez a3, .Lbnez_taken
    c.li a0, -1          /* Should be skipped */
    c.j .Lbnez_done
.Lbnez_taken:
    c.slli a0, 12        /* Shift left 12 bits -> 0xC000 */
.Lbnez_done:
    
    /* c.j: compressed unconditional jump */
    c.j .Lskip
    c.li a0, -1          /* Should be skipped */
.Lskip:
    
    /* Build result with c.addi */
    c.addi a0, 13        /* Add 13 */
    c.addi a0, 13        /* Add 13 */
    
    /* c.jr: compressed jump register (return) */
    c.jr ra

.size rvc_smoke_test, .-rvc_smoke_test

/* Disable compressed instructions after this function */
.option norvc
