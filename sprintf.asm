;A reimplementation of the C function sprintf for x86-64 asm using the NASM preprocessor.
;Does not support parsing format strings at runtime.
;Also does not currently support printing floating point numbers, but likely will eventually.


%define false	0
%define true	!false


;These two macros are required for this function, but are generally useful
%macro allocate_string 1+
	[section .rodata]
	%%string:
		db %1
	%%string_end:
	__SECT__
	%define addr %%string
	%define length %%string_end-%%string
%endmacro

%macro const_transfer 1
	%if %1 >= 8						;if there are 4 or more bytes
		mov rcx, %1 >> 2
		rep movsd
	%elif %1 >= 4					;if there are 4 to 7 bytes
		movsd
	%endif
	%if %1 & 3 >= 2				;if there are 2 or 3 bytes remaining
		movsw
	%endif
	%if %1 & 1 == 1				;if there is still 1 byte remaining
		movsb
	%endif
%endmacro


;Example usage:
;	mov r15, 1000
;	sprintf outBuffer, `Value of r15: %#010lX\n%ln`, r15, r10
;	write STDOUT_FILENO, outBuffer, r10
;
;stdout:
;	Value of r15: 0X000003E8
;
;Destroys:
;	rax, rbx, rcx, rdx, rsi, r8, r9
;Returns:
;	rdi = start addres + characters transfered
%macro sprintf 2-*
  cld
	%define start_addr %1
	mov rdi, start_addr
	%define format_str %2
	%strlen format_strlen format_str
	%define str ''
	%define i 1
	%rotate 2
	
	%rep format_strlen
	  %substr char format_str i
		
		%if char == '%'
			sprintf_next_char
			%if char == '%'
				;print a '%' (because there were two in a row)
				%strcat str str,char
				%assign i i+1
				
			%else
				;parse the flags
				%define left false
				%define plus false
				%define space false
				%define zero false
				%define pound false
				%define width 0
				%define precision 0
				%define star false
				%define dot_star false
				%rep 5
					%if   (char == '-') && (left == false)
						%assign left true
						sprintf_next_char
					%elif (char == '+') && (plus == false)
						%assign plus true
						sprintf_next_char
					%elif (char == ' ') && (space == false)
						%assign space true
						sprintf_next_char
					%elif (char == '0') && (zero == false)
						%assign zero true
						sprintf_next_char
					%elif (char == '#') && (pound == false)
						%assign pound true
						sprintf_next_char
					%endif
				%endrep
				
				%if (char == '*')
					%assign star true
					%define width %1
					%rotate 1
					sprintf_next_char
				%else
					%if (char >= '0') && (char <= '9')
						%assign width char-'0'
						sprintf_next_char
					%endif
					%if (char >= '0') && (char <= '9')
						%assign width width*10
						%assign width width+char-'0'
						sprintf_next_char
					%endif
				%endif
				
				%if (char == '.')
					%assign i i+1
					%substr char format_str i
					%if (char == '*')
						%assign dot_star true
						%define precision %1
						%rotate 1
						sprintf_next_char
					%else
						%if (char >= '0') && (char <= '9')
							%assign precision char-'0'
							sprintf_next_char
						%endif
						%if (char >= '0') && (char <= '9')
							%assign precision (precision*10)
							%assign precision (precision+char-'0')
							sprintf_next_char
						%endif
					%endif
				%endif
				;now the length field
				%define prev_char	''
				%if   (char == 'h')
					%define prev_char 'h'
					sprintf_next_char
					%if   (char == 'h')
						%define prev_char 'hh'
						sprintf_next_char
					%endif
				
				%elif	(char == 'd') || (char == 'i')
					%define prev_char 'd'
					sprintf_next_char
				
				%elif	(char == 'l')
					%define prev_char 'l'
					sprintf_next_char
					%if   (char == 'l')
						%define prev_char 'll'
						sprintf_next_char
					%endif
				%endif
				
				;now put it all together
				sprintf_print_previous_characters
				%define type_found false
				
				%if   (char == 'u')
					%if   (prev_char == 'hh')
						%define type_found true
						%define max_width 3
						movzx rbx, byte %1
						sprintf_dec_unsigned
					%elif (prev_char == 'h')
						%define type_found true
						%define max_width 5
						movzx rbx, word %1
						sprintf_dec_unsigned
					%elif (prev_char == '') || (prev_char == 'd')
						%define type_found true
						%define max_width 10
						xor rbx, rbx
						mov ebx, %1
						sprintf_dec_unsigned
					%elif (prev_char == 'l') || (prev_char == 'll')
						%define type_found true
						%define max_width 20
						mov rbx, %1
						sprintf_dec_unsigned
					%else
					%endif
				
				%elif (char == 'o')
					%if   (prev_char == 'hh')
						%define type_found true
						%define max_width 4
						movzx rbx, byte %1
						sprintf_oct
					%elif (prev_char == 'h')
						%define type_found true
						%define max_width 6
						movzx rbx, word %1
						sprintf_oct
					%elif (prev_char == '') || (prev_char == 'd')
						%define type_found true
						%define max_width 11
						xor rbx, rbx
						mov ebx, %1
						sprintf_oct
					%elif (prev_char == 'l') || (prev_char == 'll')
						%define type_found true
						%define max_width 22
						mov rbx, %1
						sprintf_oct
					%else
					%endif
				
				%elif (char == 'x')
					%if   (prev_char == 'hh')
						%define type_found true
						%define max_width 2
						movzx rbx, byte %1
						sprintf_hex_lower
					%elif (prev_char == 'h')
						%define type_found true
						%define max_width 4
						movzx rbx, word %1
						sprintf_hex_lower
					%elif (prev_char == '') || (prev_char == 'd')
						%define type_found true
						%define max_width 8
						xor rbx, rbx
						mov ebx, %1
						sprintf_hex_lower
					%elif (prev_char == 'l') || (prev_char == 'll')
						%define type_found true
						%define max_width 16
						mov rbx, %1
						sprintf_hex_lower
					%else
					%endif
				
				%elif (char == 'X')
					%if   (prev_char == 'hh')
						%define type_found true
						%define max_width 2
						movzx rbx, byte %1
						sprintf_hex_upper
					%elif (prev_char == 'h')
						%define type_found true
						%define max_width 4
						movzx rbx, word %1
						sprintf_hex_upper
					%elif (prev_char == '') || (prev_char == 'd')
						%define type_found true
						%define max_width 8
						xor rbx, rbx
						mov ebx, %1
						sprintf_hex_upper
					%elif (prev_char == 'l') || (prev_char == 'll')
						%define type_found true
						%define max_width 16
						mov rbx, %1
						sprintf_hex_upper
					%else
					%endif
				
				%elif (char == 'c')
					%if   (prev_char == '')
						%define type_found true
						mov al, %1
						stosb
					%elif (prev_char == 'l')
						%define type_found true
						mov ax, %1
						stosw
					%else
					%endif
				
				%elif (char == 's')
					%if   (star == true)
						%if   (prev_char == '')
							%define type_found true
							mov rsi, %1
							movzx rcx, byte width
							inc rcx
							jmp %%start
							%%loop:
							stosb
							%%start:
							lodsb
							cmp al, 0
							loopne %%loop
						%elif (prev_char == 'l')
							%define type_found true
							mov rsi, %1
							movzx rcx, byte width
							inc rcx
							jmp %%start
							%%loop:
							stosw
							%%start:
							lodsw
							cmp ax, 0
							loopne %%loop
						%else
						%endif
					%else
						%if (prev_char == '')
							%define type_found true
							mov rsi, %1
							%if (width != 0)
								mov rcx, width+1
							%endif
							jmp %%start
							%%loop:
							stosb
							%%start:
							lodsb
							cmp al, 0
							%if (width == 0)
								jne %%loop
							%else
								loopne %%loop
							%endif
						%elif (prev_char == 'l')
							%define type_found true
							mov rsi, %1
							%if (width != 0)
								mov rcx, width+1
							%endif
							jmp %%start
							%%loop:
							stosw
							%%start:
							lodsw
							cmp ax, 0
							%if (width == 0)
								jne %%loop
							%else
								loopne %%loop
							%endif
						%else
						%endif
					%endif
				
				%elif (char == 'n')
					%if   (prev_char == 'hh')
						%define type_found true
						mov rax, rdi
						sub rax, start_addr
						mov %1, al
					%elif (prev_char == 'h')
						%define type_found true
						mov rax, rdi
						sub rax, start_addr
						mov %1, ax
					%elif (prev_char == '') || (prev_char == 'd')
						%define type_found true
						mov rax, rdi
						sub rax, start_addr
						mov %1, eax
					%elif (prev_char == 'l') || (prev_char == 'll')
						%define type_found true
						mov rax, rdi
						sub rax, start_addr
						mov %1, rax
					%else
					%endif
				%endif
				
				%if (type_found == true)
					%assign i i+1
				%else
					%if   (prev_char == 'hh')
						%assign char 'd'
						%define max_width 3
						movzx rbx, byte %1
						sprintf_dec 'byte'
					
					%elif (prev_char == 'h')
						%assign char 'd'
						%define max_width 5
						movzx rbx, word %1
						sprintf_dec 'word'
					
					%elif (prev_char == 'd')
						%assign char 'd'
						%define max_width 10
						xor rbx, rbx
						mov ebx, %1
						sprintf_dec 'dword'
					
					%elif (prev_char == 'l') || (prev_char == 'll')
						%assign char 'd'
						%define max_width 20
						mov rbx, %1
						sprintf_dec 'qword'
					
					%else
						%define str ''
						%strcat str 'unrecognized type "', char, '"'
						%fatal str
					%endif
				%endif
				%rotate 1
			%endif
		
		%else
			%strcat str str,char
			%assign i i+1
		%endif
		
		%if i > format_strlen	;at the end of the format string
			sprintf_print_previous_characters
		  %exitrep
		%endif
	%endrep
%endmacro




%macro sprintf_next_char 0
	%assign i i+1
	%substr char format_str i
%endmacro

%macro sprintf_print_previous_characters 0
	allocate_string str
	mov rsi, addr
	const_transfer length
	%define str ''
%endmacro




%macro sprintf_hex_upper 0
	%if (star == true)
		movzx r8, byte width
	%else
		mov r8, width
	%endif
	%if (pound == true)
		cmp rbx, 0
		je %%done
		setnz r9b				;extra characters flag
		xor rax, rax
		sub r8, 2
		cmovs r8, rax
		%%done:
	%endif
	movapd xmm2, [correctAtoF_Uppercase]
	call sprintf_hex_func
	sprintf_number
%endmacro

%macro sprintf_hex_lower 0
	%if (star == true)
		movzx r8, byte width
	%else
		mov r8, width
	%endif
	%if (pound == true)
		cmp rbx, 0
		je %%done
		setnz r9b				;extra characters flag
		xor rax, rax
		sub r8, 2
		cmovs r8, rax
		%%done:
	%endif
	movapd xmm2, [correctAtoF_Lowercase]
	call sprintf_hex_func
	sprintf_number
%endmacro

%macro sprintf_oct 0
	%if (star == true)
		movzx r8, byte width
	%else
		mov r8, width
	%endif
	%if (pound == true)
		cmp rbx, 0
		je %%done
		setnz r9b				;extra characters flag
		xor rax, rax
		dec r8
		cmovs r8, rax
		%%done:
	%endif
	mov rcx, max_width
	call sprintf_oct_func
	sprintf_number
%endmacro

%macro sprintf_dec_unsigned 0
	%if (star == true)
		movzx r8, byte width
	%else
		mov r8, width
	%endif
	mov rcx, max_width
	call sprintf_dec_func
	sprintf_number
%endmacro

%macro sprintf_dec 1
	%if (star == true)
		movzx r8, byte width
		%if (plus == true || space == true)
			xor rax, rax
			dec r8
			cmovs r8, rax
		%endif
	%else
		%if (plus == true || space == true) && (width > 0)	;a sign is always printed
			mov r8, width-1
		%else
			mov r8, width
		%endif
	%endif
	%if   %1 == 'byte'
		cmp bl, 0
		jns %%positive
		neg bl
	%elif %1 == 'word'
		cmp bx, 0
		jns %%positive
		neg bx
	%elif %1 == 'dword'
		cmp ebx, 0
		jns %%positive
		neg ebx
	%elif %1 == 'qword'
		cmp rbx, 0
		jns %%positive
		neg rbx
	%endif
	setns r9b				;extra characters flag
	%if (plus != true) && (space != true)
		xor rax, rax
		dec r8
		cmovs r8, rax
	%endif
	%%positive:
	mov rcx, max_width
	call sprintf_dec_func
	sprintf_number
%endmacro




%macro sprintf_number 0	
	mov rcx, max_width
	mov rsi, (asciiBuffer + 32-max_width)
	call sprintf_number_func
	;rdx is now number length
	;r8 is now padding length
	;r9 is the extra characters flag
	%if (zero == true)
		sprintf_extra
		%if (left == false)
			mov rcx, r8
			mov al, '0'
			rep stosb
		%endif
		mov rcx, rdx
		rep movsb
		%if (left == true)
			mov rcx, r8
			mov al, '0'
			rep stosb
		%endif
	%else
		%if (left == false)
			mov rcx, r8
			mov al, ' '
			rep stosb
		%endif
		sprintf_extra
		mov rcx, rdx
		rep movsb
		%if (left == true)
			mov rcx, r8
			mov al, ' '
			rep stosb
		%endif
	%endif
%endmacro

%macro sprintf_extra 0
	%if (pound == true) && (char == 'X')
		cmp r9b, 0
		je %%done
		mov ax, '0X'
		stosw
		%%done:
	%elif (pound == true) && (char == 'x')
		cmp r9b, 0
		je %%done
		mov ax, '0x'
		stosw
		%%done:
	%elif (pound == true) && (char == 'o')
		cmp r9b, 0
		je %%done
		mov al, '0'
		stosb
		%%done:
	%elif (char == 'd')
		%if   (plus == true)
			mov bl, '-'
			mov al, '+'
			cmp r9b, 0
			cmovne rax, rbx
			stosb
		%elif (space == true)
			mov bl, '-'
			mov al, ' '
			cmp r9b, 0
			cmovne rax, rbx
			stosb
		%else
			cmp r9b, 0
			je %%done
			mov al, '-'
			stosb
			%%done:
		%endif
	%endif
%endmacro




section .bss
%ifndef ASCIIBUFFER
	%define ASCIIBUFFER
	align 16
	asciiBuffer	resb 32
%endif


section .rodata
align 16
lowNibbleMask:	db 0xF, 0xF, 0xF, 0xF, 0xF, 0xF, 0xF, 0xF
								db 0xF, 0xF, 0xF, 0xF, 0xF, 0xF, 0xF, 0xF
checkIfAtoF:		db 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
correctAtoF_Uppercase:
								db 248, 248, 248, 248, 248, 248, 248, 248
								db 248, 248, 248, 248, 248, 248, 248, 248
correctAtoF_Lowercase:
								db 216, 216, 216, 216, 216, 216, 216, 216
								db 216, 216, 216, 216, 216, 216, 216, 216
asciiNumStart:	db 48, 48, 48, 48, 48, 48, 48, 48
								db 48, 48, 48, 48, 48, 48, 48, 48


section .text
sprintf_hex_func:
	bswap rbx											;reverse the order of bytes (number needs to be backwards)
	movq xmm1, rbx								;move low nibble qword into low qword of xmm1
	shr rbx, 4
	movq xmm0, rbx 								;move high nibble qword into low qword of xmm0
	punpcklbw xmm0, xmm1					;interleave bytes
	pand xmm0, [lowNibbleMask]		;and with mask to get low nibbles of xmm0
	movapd xmm1, xmm0
	pcmpgtb xmm1,[checkIfAtoF]		;find what numbers are represened as A through F
	psubusb xmm1, xmm2						;subtract with saturation to yield 7s or 39s depending on case
	paddb	xmm1, [asciiNumStart]		;add the ascci base number offset
	paddb xmm0, xmm1							;add xmm1 to xmm0 to obtain correct ascii values
	movapd [asciiBuffer+16], xmm0
	ret
	
sprintf_oct_func:
	push rdi
	mov rdi, (asciiBuffer+31)		;the middle of the buffer
	std													;in order to write backwards
	jmp .start
.loop:
	shr rbx, 3
.start:
	mov rax, rbx
	and al, 0x7			;extract the rightmost 3 bits
	add rax, '0'		;ascii number offset
	stosb
	loop .loop
	cld
	pop rdi
	ret
	
sprintf_dec_func:
	push rdi
	push r8
	push r9
	push r10
	mov rdi, (asciiBuffer+31)		;the middle of the buffer
	std													;in order to write backwards
	mov r9, 0xCCCCCCCCCCCCCCCD	;reciporical for dividing qword by 10
	mov r10, 10
	xor rdx, rdx
.loop:
	mov r8, rbx		;make a backup of the original number for modulus
	mov rax, rbx
	mul r9					;0xCCCCCCCCCCCCCCCD
	mov rax, rdx
	shr rax, 3			;rax is now divided by 10
	mov rbx, rax		;perserve the quotient for the next digit
	mul r10					;10
	neg rax
	add rax, r8			;subtract the rounded down number from the original
	add rax, '0'		;ascii number offset
	stosb
	loop .loop
	cld
	pop r10
	pop r9
	pop r8
	pop rdi					;restore the original destination address
	ret
	
sprintf_number_func:
	lodsb
	cmp al, '0'
	loope sprintf_number_func
	inc rcx
	dec rsi
	mov rdx, rcx		;store how many places are left
	xor rax, rax
	sub r8, rcx			;subtract how many places are remaining from the width
	cmovs r8, rax
	ret