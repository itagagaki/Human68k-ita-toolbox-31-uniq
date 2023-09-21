* uniq - uniq line
*
* Itagaki Fumihiko 15-Jan-95  Create.
* 1.0
*
* Usage: uniq [ -udcSBCZ ] [ -f <fields> ] [ -s <chars> ] [ -w <chars> ]
*        [ -<fields> ] [ +<chars> ] [ -- ] [ <input> [ <output> ] ]

.include doscall.h
.include chrcode.h
.include stat.h

.xref DecodeHUPAIR
.xref isdigit
.xref isspace2
.xref issjis
.xref atou
.xref utoa
.xref strlen
.xref strfor1
.xref memcmp
.xref memmovi
.xref printfi
.xref strip_excessive_slashes

STACKSIZE	equ	2048

READSIZE	equ	8192
INPBUFSIZE_MIN	equ	258
OUTBUF_SIZE	equ	8192

CREATE_MODE	equ	MODEVAL_ARC

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_u		equ	0	*  -u
FLAG_d		equ	1	*  -d
FLAG_c		equ	2	*  -c
FLAG_S		equ	3	*  -S
FLAG_B		equ	4	*  -B
FLAG_C		equ	5	*  -C
FLAG_Z		equ	6	*  -Z
FLAG_eof	equ	7


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : フラグ
		clr.l	skip_fields
		clr.l	skip_chars
		move.l	#-1,check_chars
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		lea	skip_chars(pc),a1
		cmpi.b	#'+',(a0)
		beq	number_option_0

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		move.b	1(a0),d0
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		lea	skip_fields(pc),a1
		bsr	isdigit
		beq	number_option_1

		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_u,d1
		cmp.b	#'u',d0
		beq	set_option

		moveq	#FLAG_d,d1
		cmp.b	#'d',d0
		beq	set_option

		moveq	#FLAG_c,d1
		cmp.b	#'c',d0
		beq	set_option

		moveq	#FLAG_S,d1
		cmp.b	#'S',d0
		beq	set_option

		lea	skip_fields(pc),a1
		cmp.b	#'f',d0
		beq	number_option

		lea	skip_chars(pc),a1
		cmp.b	#'s',d0
		beq	number_option

		lea	check_chars(pc),a1
		cmp.b	#'w',d0
		beq	number_option

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_B_found:
		bclr	#FLAG_C,d5
		bset	#FLAG_B,d5
		bra	set_option_done

option_C_found:
		bclr	#FLAG_B,d5
		bset	#FLAG_C,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

number_option:
		tst.b	(a0)
		bne	number_option_1
number_option_0:
		subq.l	#1,d7
		bcs	too_few_args

		addq.l	#1,a0
number_option_1:
		bsr	atou
		bne	bad_arg

		tst.b	(a0)+
		bne	bad_arg

		move.l	d1,(a1)
		bra	decode_opt_loop1

decode_opt_done:
		cmp.l	#2,d7
		bhi	too_many_args

		btst	#FLAG_u,d5
		bne	opt_ok

		btst	#FLAG_d,d5
		bne	opt_ok

		bset	#FLAG_u,d5
		bset	#FLAG_d,d5
opt_ok:
	*
	*  入力バッファを確保する
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#INPBUFSIZE_MIN,d0
		blo	insufficient_memory

		move.l	d0,inpbuf_size
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin
		bmi	move_stdin_done

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
move_stdin_done:
	*
	*  入力をオープン
	*
		tst.l	d7
		beq	input_stdin

		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		subq.l	#1,d7
		cmpi.b	#'-',(a0)
		bne	input_file

		tst.b	1(a0)
		bne	input_file
input_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin,d0
		bra	input_opened

input_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
input_opened:
		move.l	a0,input_name
		move.l	d0,input_handle
		bpl	input_ok

			lea	msg_open_fail(pc),a2
			bsr	werror_myname_word_colon_msg
			moveq	#2,d0
			bra	exit_program

input_ok:
	*
	*  出力をオープン
	*
		tst.l	d7
		beq	output_stdout

		cmpi.b	#'-',(a1)
		bne	output_file

		tst.b	1(a1)
		bne	output_file
output_stdout:
		lea	msg_stdout(pc),a0
		moveq	#1,d0
		bra	output_ok

output_file:
		clr.w	-(a7)				*  まず読み込みモードで
		move.l	a1,-(a7)			*  出力先ファイルを
		DOS	_OPEN				*  オープンしてみる
		addq.l	#6,a7
		move.l	d0,d1
		bmi	create_output

		bsr	is_chrdev
		and.w	#$80,d0
		move.w	d0,-(a7)
		move.w	d1,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
		tst.w	(a7)+				*  キャラクタ・デバイスならば
		bne	open_output			*  　オープンする（新規作成しない）
create_output:
		move.w	#CREATE_MODE,-(a7)
		move.l	a1,-(a7)
		DOS	_CREATE
		bra	output_opened

open_output:
		move.w	#1,-(a7)
		move.l	a1,-(a7)
		DOS	_OPEN
output_opened:
		addq.l	#6,a7
		tst.l	d0
		bpl	output_ok

			movea.l	a1,a0
			bsr	werror_myname_word_colon_msg
			lea	msg_create_fail(pc),a2
			moveq	#3,d0
			bra	exit_program

output_ok:
		move.l	d0,output_handle
		move.l	a1,output_name
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering
		beq	check_output_done		*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	check_output_done

		*  cooked character device
		btst	#FLAG_B,d5
		bne	check_output_done

		bset	#FLAG_C,d5			*  改行を変換する
check_output_done:
	*
	*  メイン処理
	*
		lea	outbuf(pc),a0
		move.l	a0,outbuf_ptr
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		*
		bsr	uniq
		bsr	flush_outbuf
		moveq	#0,d0
exit_program:
		move.w	d0,-(a7)
		move.l	stdin,d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
		addq.l	#4,a7
exit_program_1:
		DOS	_EXIT2

bad_arg:
		lea	msg_bad_arg(pc),a0
		bra	werror_usage

too_many_args:
		lea	msg_too_many_args(pc),a0
		bra	werror_usage

too_few_args:
		lea	msg_too_few_args(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d0
		bra	exit_program
****************************************************************
* uniq
****************************************************************
uniq:
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz
		sf	terminate_by_ctrld
		move.l	input_handle,d0
		bsr	is_chrdev
		beq	uniq_1				*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	uniq_1

		st	terminate_by_ctrlz
		st	terminate_by_ctrld
uniq_1:
		bclr	#FLAG_eof,d5
		movea.l	inpbuf_top,a2
		moveq	#0,d2
		clr.l	line1_length
		bsr	getline
uniq_loop1:
		move.l	a3,line1_top
		move.l	d3,line1_length
		beq	uniq_return

		move.l	a4,line1_skip_top
		move.l	d4,line1_skip_length
		moveq	#0,d6				*  D6.L : 反復count
uniq_loop2:
		bsr	getline
		tst.l	d3
		beq	uniq_output

		bsr	compare
		bne	uniq_output

		addq.l	#1,d6
		bra	uniq_loop2

uniq_output:
		bsr	output
		bra	uniq_loop1
*****************************************************************
compare:
		movem.l	d3-d4,-(a7)
		movea.l	line1_skip_top,a0
		movea.l	a4,a1
		move.l	line1_skip_length,d3
		cmp.l	d3,d4
		bls	compare_1

		exg	d3,d4
compare_1:
		move.l	check_chars,d0
		cmp.l	d3,d0
		bhi	compare_2

		cmp.l	d4,d0
		bhi	compare_return			*  NE
		bra	do_compare

compare_2:
		move.l	d3,d0
		cmp.l	d4,d0
		bne	compare_return			*  NE
do_compare:
		bsr	memcmp
compare_return:
		movem.l	(a7)+,d3-d4
		rts
*****************************************************************
output:
		btst	#FLAG_c,d5
		bne	output_c

		tst.l	d6
		beq	output_u
output_d:
		btst	#FLAG_d,d5
		bra	output_1

output_u:
		btst	#FLAG_u,d5
output_1:
		bne	output_2
uniq_return:
output_done:
		rts

output_c:
		movem.l	d2-d4/a2,-(a7)
		move.l	d6,d0
		addq.l	#1,d0
		moveq	#0,d1
		moveq	#' ',d2
		moveq	#4,d3
		moveq	#1,d4
		lea	utoa(pc),a0
		lea	putc(pc),a1
		suba.l	a2,a2
		bsr	printfi
		movem.l	(a7)+,d2-d4/a2
		moveq	#' ',d0
		bsr	putc
output_2:
		movea.l	line1_top,a0
		move.l	line1_length,d1
output_loop:
		subq.l	#1,d1
		bcs	output_done

		move.b	(a0)+,d0
		btst	#FLAG_C,d5
		beq	output_4

			cmp.b	#CR,d0
			bne	output_3

				tst.l	d1
				beq	output_4

				cmpi.b	#LF,(a0)
				bne	output_4

				bsr	putc
				subq.l	#1,d1
				move.b	(a0)+,d0
				bra	output_4

output_3:
			cmp.b	#LF,d0
			bne	output_4

				moveq	#CR,d0
				bsr	putc
				moveq	#LF,d0
output_4:
		bsr	putc
		bra	output_loop
*****************************************************************
* getline
*
* CALL
*      none.
*
* RETURN
*      A3     入力した行の先頭アドレス
*      D3.L   入力した行の長さ
*      A4     入力した行の比較アドレス
*      D4.L   入力した行の比較アドレスからの長さ
*
* NOTE
*      line1_top から line1_length までのデータは保存される.
*      line1_top と line1_skip_top は移動することがある.
*****************************************************************
getline:
		moveq	#0,d3
getline_loop:
		tst.l	d2
		bne	getc_get1

		btst	#FLAG_eof,d5
		bne	getc_eof

		move.l	inpbuf_top,d0
		add.l	inpbuf_size,d0
		sub.l	a2,d0
		bne	getc_read

		movea.l	inpbuf_top,a0
		move.l	line1_length,d0
		beq	getline_gb_2

		movea.l	line1_top,a1
		move.l	a1,d1
		sub.l	a0,d1
		beq	getline_gb_1

		bsr	memmovi
		sub.l	d1,line1_top
		sub.l	d1,line1_skip_top
		bra	getline_gb_2

getline_gb_1:
		adda.l	d0,a0
getline_gb_2:
		move.l	d3,d0
		beq	getline_gb_4

		movea.l	a2,a1
		suba.l	d3,a1
		cmpa.l	a0,a1
		beq	getline_gb_3

		bsr	memmovi
		bra	getline_gb_4

getline_gb_3:
		adda.l	d3,a0
getline_gb_4:
		movea.l	a0,a2
		move.l	inpbuf_top,d0
		add.l	inpbuf_size,d0
		sub.l	a2,d0
		beq	insufficient_memory
getc_read:
		cmp.l	#READSIZE,d0
		bls	getc_read_1

		move.l	#READSIZE,d0
getc_read_1:
		move.l	d0,-(a7)
		move.l	a2,-(a7)
		move.l	input_handle,d0
		move.w	d0,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d2
		bmi	read_fail

		tst.b	terminate_by_ctrlz
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	terminate_by_ctrld
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d2
		beq	getc_eof
getc_get1:
		moveq	#0,d0
		move.b	(a2)+,d0
		subq.l	#1,d2
		addq.l	#1,d3
		cmp.b	#LF,d0
		bne	getline_loop
getline_done:
		movea.l	a2,a3
		suba.l	d3,a3
		movea.l	a3,a4
		move.l	d3,d4
		move.l	skip_fields,d1
		beq	skip_field_done
skip_field_loop1:
		subq.l	#1,d4
		bcs	skip_field_break

		move.b	(a4)+,d0
		bsr	isspace2
		beq	skip_field_loop1
skip_field_loop2:
		subq.l	#1,d4
		bcs	skip_field_break

		move.b	(a4)+,d0
		bsr	isspace2
		bne	skip_field_loop2

		subq.l	#1,d1
		bne	skip_field_loop1

		subq.l	#1,a4
skip_field_break:
		addq.l	#1,d4
skip_field_done:
		btst	#FLAG_S,d5
		beq	skip_blank_done
skip_blank_loop:
		subq.l	#1,d4
		bcs	skip_blank_break

		move.b	(a4)+,d0
		bsr	isspace2
		beq	skip_blank_loop

		subq.l	#1,a4
skip_blank_break:
		addq.l	#1,d4
skip_blank_done:
		move.l	skip_chars,d1
		cmp.l	d4,d1
		bls	skip_char_1

		move.l	d4,d1
skip_char_1:
		adda.l	d1,a4
		sub.l	d1,d4
		rts

getc_eof:
		bset	#FLAG_eof,d5
		bra	getline_done
*****************************************************************
trunc:
		move.l	d2,d1
		beq	trunc_done

		movea.l	a2,a0
trunc_find_loop:
		cmp.b	(a0)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a0
		move.l	a0,d2
		sub.l	a2,d2
		bset	#FLAG_eof,d5
trunc_done:
		rts
*****************************************************************
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.l	output_handle,d0
		move.w	d0,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr,a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr
		subq.l	#1,outbuf_free
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
flush_outbuf:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_return

		move.l	d0,-(a7)
		pea	outbuf(pc)
		move.l	output_handle,d0
		move.w	d0,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		lea	outbuf(pc),a0
		move.l	a0,outbuf_ptr
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_return:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
		bra	exit_3
*****************************************************************
read_fail:
		movea.l	input_name,a0
		lea	msg_read_fail(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	werror_exit_3
*****************************************************************
write_fail:
		movea.l	output_name,a0
		lea	msg_write_fail(pc),a2
werror_exit_3:
		bsr	werror_myname_word_colon_msg
exit_3:
		moveq	#3,d0
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	str_colon(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## uniq 1.0 ##  Copyright(C)1995 by Itagaki Fumihiko',0

msg_myname:		dc.b	'uniq'
str_colon:		dc.b	': ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_bad_arg:		dc.b	'引数が正しくありません',0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_too_many_args:	dc.b	'引数が多過ぎます',0
msg_create_fail:	dc.b	'作成できません',CR,LF,0
msg_open_fail:		dc.b	'オープンできません',CR,LF,0
msg_read_fail:		dc.b	'入力エラー',CR,LF,0
msg_write_fail:		dc.b	'出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_stdout:		dc.b	'- 標準出力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:		dc.b	CR,LF
	dc.b	'使用法:  uniq [-udcSBCZ] [-f <#>] [-s <#>] [-w <#>] [-<#>] [+<#>] [--] [<input> [<output>]] ...',CR,LF,0
*****************************************************************
.bss
.even
stdin:			ds.l	1
input_name:		ds.l	1
output_name:		ds.l	1
input_handle:		ds.l	1
output_handle:		ds.l	1
inpbuf_top:		ds.l	1
inpbuf_size:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
skip_fields:		ds.l	1
skip_chars:		ds.l	1
check_chars:		ds.l	1
line1_top:		ds.l	1
line1_length:		ds.l	1
line1_skip_top:		ds.l	1
line1_skip_length:	ds.l	1
do_buffering:		ds.b	1
terminate_by_ctrlz:	ds.b	1
terminate_by_ctrld:	ds.b	1
outbuf:			ds.b	OUTBUF_SIZE
.even
			ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
