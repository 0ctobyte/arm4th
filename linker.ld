ENTRY(_start)
SECTIONS
{
	. = 0x0;
	
	/* Align to page (4 kb) boundary */
	.text ALIGN(0x1000) : AT(ADDR(.text)) {
    *(.text)
	}
}

