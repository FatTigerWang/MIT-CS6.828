# MIT-CS6.828

## 内核加载顺序

BIOS 程序硬件检测完成后会将硬盘引导扇区加载到0x7c00至0x7dff的内存地址中，然后设置PC为`0x7c00`执行`boot.S`

`boot.S`将CPU从`real mode`转换为`protected mode`，这将启用`32`位寻址空间，然后设置栈指针为0x7c00，栈空间增加时，栈指针地址递减，所以这将是一个固定大小的栈空间。设置完栈指针后，调用`main.c`。

`main.c`扫描硬盘的第一页，加载`ELF`格式的文件头，根据`ELF`的文件定义将内核加载到指定内存地址（`0x00100000`），然后跳转到内核程序入口（`0x0010000c`）开始执行`entry.S`。

`entry.S`之前使用的都为物理地址，`entry.S`则将`entrypgdir.c`中定义的页目录加载到`cr3`寄存器，这会将物理地址前`4MB`(`0x000000`-`0x3ff000`)映射到虚拟地址`KERNBASE+4MB`的位置。然后设置`cr0`寄存器以开启分页，最后设置`%esp`指定栈指针位置后跳转到`i386_init.c`
