#include <inc/mmu.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.
# 整段代码内容就是将CPU从一开始的实模式切换到保护模式,实模式下只能操作16位内存地址空间(1MB).保护模式可以启用32位地址空间(4GB)
# BIOS将硬盘第一个扇区数据读取到物理内存地址0x7c00(cs=0 ip=7c00)上并使用实模式执行
# 分段地址就是为了在CPU只有16位寄存器时通过两个寄存器(CS<<4+IP)存一个物理地址的骚操作，因为当年的CPU地址线具有20根，也就是20位寄存器才能存储下，

# 定义几个常量后续会用到
.set PROT_MODE_CSEG, 0x8         # kernel code segment selector
.set PROT_MODE_DSEG, 0x10        # kernel data segment selector
.set CR0_PE_ON,      0x1         # protected mode enable flag

# 暴露出start方法给外部调用，链接器链接时需要用到
.globl start
# 开始标记
start:
  # 以16位模式运行
  .code16                     # Assemble for 16-bit mode
  # 禁用中断
  cli                         # Disable interrupts
  # 清除顺序(设置字符串操作为递增)
  cld                         # String operations increment

  # Set up the important data segment registers (DS, ES, SS).
  # 其实就是将这几个寄存器清零
  # xor %ax,%ax，一个异或操作，自己异或自己=0
  xorw    %ax,%ax             # Segment number zero
  # 将寄存器ax的值移动到ds寄存器，以下同理
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # Enable A20:
  #   For backwards compatibility with the earliest PCs, physical
  #   address line 20 is tied low, so that addresses higher than
  #   1MB wrap around to zero by default.  This code undoes this.
  # 遥想当年的CPU寄存器只有16位，而CPU的地址线则有20根，
  # 16位寄存器无法表示完整的20根地址线的寻址空间（1MB），于是有了分段地址这种操作。
  # 将一个寄存器的地址作为分段地址，另一个寄存器作为OFFSET，
  # 合并到一起用来表示20根地址线的寻址空间（1MB），表示方式如下：
  # 分段地址左移4位+OFFSET，换算成二进制能得到一个20位的地址，超过20位，则CPU地址线不够，
  # 所以会将第21个bit(bit位是从0开始数的，第20位其实是第21个bit位)始终设置为0
  # 因此，这里需要启用A20
  # 怎么激活呢，由于历史原因A20地址位由键盘控制器芯片8042管理。所以要给8042发命令激活A20
  # 8042有两个IO端口：0x60和0x64
  # 激活流程位： 发送0xd1命令到0x64端口 --> 发送0xdf到0x60
  # 发送命令给端口前先判断端口缓冲区是否为空
seta20.1:
  # in操作是将目标地址0x64端口数据读取到al寄存器
  inb     $0x64,%al               # Wait for not busy
  # 判断al寄存器值第二位是否为1 test指令用来将 $0x2 & $al，并将结果设置给ZF标志寄存器
  testb   $0x2,%al
  # 判断ZF的值，如果缓冲区被占用跳转到seta20.1重新检测
  jnz     seta20.1

  # 将0xd1值移动到寄存器al，由于in与out操作都只能从寄存器进行操作，所以这里先移动数据到寄存器
  movb    $0xd1,%al               # 0xd1 -> port 0x64
  # 发送寄存器中的数据到端口
  outb    %al,$0x64

# 同上seta20.1
seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60

  # Switch from real to protected mode, using a bootstrap GDT
  # and segment translation that makes virtual addresses 
  # identical to their physical addresses, so that the 
  # effective memory map does not change during the switch.
  lgdt    gdtdesc
  # cr0寄存器中的第0位用来设置是否为保护模式(Protedted Enable)，设置为1表示启动保护模式
  # 先移动cr0寄存器中的数据到eax寄存器
  movl    %cr0, %eax
  # 做一个或操作，CR0_PE_ON为我们一开始定义的常量，值就是1，这个操作就是将寄存器eax中的数据第0位设置为1
  orl     $CR0_PE_ON, %eax
  # 将eax寄存器数据移动到cr0寄存器，至此已经开启保护模式
  movl    %eax, %cr0
  
  # Jump to next instruction, but in 32-bit code segment.
  # Switches processor into 32-bit mode.
  ljmp    $PROT_MODE_CSEG, $protcseg
  # 使用32位模式
  .code32                     # Assemble for 32-bit mode
protcseg:
  # Set up the protected-mode data segment registers
  movw    $PROT_MODE_DSEG, %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS
  movw    %ax, %ss                # -> SS: Stack Segment
  
  # Set up the stack pointer and call into C.
  # 设置栈指针为0x7c00
  movl    $start, %esp
  # 调用内核
  call bootmain

  # If bootmain returns (it shouldn't), loop.
  # 理论上call kernel代码后永远不会退出，但是如果真的退出，这里进行了一个循环
spin:
  jmp spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULL				# null seg
  SEG(STA_X|STA_R, 0x0, 0xffffffff)	# code seg
  SEG(STA_W, 0x0, 0xffffffff)	        # data seg

gdtdesc:
  .word   0x17                            # sizeof(gdt) - 1
  .long   gdt                             # address gdt

