#include <inc/x86.h>
#include <inc/elf.h>

/**********************************************************************
 * This a dirt simple boot loader, whose sole job is to boot
 * an ELF kernel image from the first IDE hard disk.
 *
 * DISK LAYOUT
 *  * This program(boot.S and main.c) is the bootloader.  It should
 *    be stored in the first sector of the disk.
 *
 *  * The 2nd sector onward holds the kernel image.
 *
 *  * The kernel image must be in ELF format.
 *
 * BOOT UP STEPS
 *  * when the CPU boots it loads the BIOS into memory and executes it
 *
 *  * the BIOS intializes devices, sets of the interrupt routines, and
 *    reads the first sector of the boot device(e.g., hard-drive)
 *    into memory and jumps to it.
 *
 *  * Assuming this boot loader is stored in the first sector of the
 *    hard-drive, this code takes over...
 *
 *  * control starts in boot.S -- which sets up protected mode,
 *    and a stack so C code then run, then calls bootmain()
 *
 *  * bootmain() in this file takes over, reads in the kernel and jumps to it.
 **********************************************************************/

//定义扇区大小
#define SECTSIZE	512
//定义ELF头文件在内存中的位置
#define ELFHDR		((struct Elf *) 0x10000) // scratch space

void readsect(void*, uint32_t);
void readseg(uint32_t, uint32_t, uint32_t);

void
bootmain(void)
{
	//定义program header 结构指针，这两个指针将指向内存中segment开始和结尾的地址
	struct Proghdr *ph, *eph;

	//将第一页加载到ELFHDR内存空间处
	readseg((uint32_t) ELFHDR, SECTSIZE*8, 0);

	//检测刚加载到ELFHDR处的数据是否是ELFHDR
	if (ELFHDR->e_magic != ELF_MAGIC)
		goto bad;

	//指定内存中的program segment起始地址为ELFHDR+ELFHDR->e_phoff就是从ELFHDR结束开始e_phoff为ELFHD结束位置的偏移量
	ph = (struct Proghdr *) ((uint8_t *) ELFHDR + ELFHDR->e_phoff);
	//指定内存中最后一个program segment地址
	eph = ph + ELFHDR->e_phnum;
	//循环将扇区的program segment加载到内存中
	for (; ph < eph; ph++)
		//指针++则表示指针指向的地址+指针数据结构大小*2，这里可以看成指针指向下一个program segment
		//ph->p_pa为需要加载到内存中地址的起始位置，ph->p_memsz为需要的内存大小，ph->p_offset为program segment
		//数据所在硬盘上的基于ELFHDR起始地址的偏移量
		readseg(ph->p_pa, ph->p_memsz, ph->p_offset);

	//跳转到内核入口处(示例中ELF入口指定为0x0010000c处，内核代码被加载到由ELF指定的LMA：0x00100000处)
	((void (*)(void)) (ELFHDR->e_entry))();

bad:
	outw(0x8A00, 0x8A00);
	outw(0x8A00, 0x8E00);
	while (1)
		/* do nothing */;
}

// Read 'count' bytes at 'offset' from kernel into physical address 'pa'.
// Might copy more than asked
void
readseg(uint32_t pa, uint32_t count, uint32_t offset)
{
	//program segment在内存中的结束地址
	uint32_t end_pa;
	//由起始地址+内存大小
	end_pa = pa + count;

	pa &= ~(SECTSIZE - 1);

	//将偏移量转换为扇区
	offset = (offset / SECTSIZE) + 1;

	// If this is too slow, we could read lots of sectors at a time.
	// We'd write more to memory than asked, but it doesn't matter --
	// we load in increasing order.
	//循环读取
	while (pa < end_pa) {
		// 将一个扇区读取到指定的内存位置
		readsect((uint8_t*) pa, offset);
		pa += SECTSIZE;
		offset++;
	}
}

void
waitdisk(void)
{
	// wait for disk reaady
	while ((inb(0x1F7) & 0xC0) != 0x40)
		/* do nothing */;
}

void
readsect(void *dst, uint32_t offset)
{
	// 等待硬盘准备好
	waitdisk();
	// 设置读取扇区的数目为1
	outb(0x1F2, 1);		// count = 1
	outb(0x1F3, offset);
	outb(0x1F4, offset >> 8);
	outb(0x1F5, offset >> 16);
	outb(0x1F6, (offset >> 24) | 0xE0);
	outb(0x1F7, 0x20);	// 0x20命令，读取扇区
	
	//上面四条指令联合制定了扇区号
	//在这4个字节线联合构成的32位参数中
	//29-31位强制设为1
	//28位(=0)表示访问"Disk 0"
	//0-27位是28位的偏移量

	waitdisk();

	// 读取数据到目标内存位置，每次读取128 bit读取4次
	insl(0x1F0, dst, SECTSIZE/4);
}

